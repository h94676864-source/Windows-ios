import Foundation
import Darwin

struct WinlatorWineRuntimeStatus {
    let title: String
    let detail: String
}

/// Contract for an embedded, iOS-signed WineRuntime.framework:
/// - WinlatorWineRuntimeABI = "ios-arm64-inprocess"
/// - exported uint32_t winlator_wine_abi_version(void)
/// - exported int32_t winlator_wine_run_json(const char *utf8_json)
///
/// The JSON request contains executablePath, prefixPath, workingDirectory and arguments.
/// The framework must execute Wine in-process; iOS does not provide fork/exec for app binaries.
enum WinlatorWineRuntimeAdapter {
    private static let expectedABI: UInt32 = 1
    private static let versionSymbol = "winlator_wine_abi_version"
    private static let runSymbol = "winlator_wine_run_json"
    private static let lock = NSLock()
    private static var loadedHandle: UnsafeMutableRawPointer?

    private typealias VersionFunction = @convention(c) () -> UInt32
    private typealias RunFunction = @convention(c) (UnsafePointer<CChar>?) -> Int32

    private struct LaunchRequest: Encodable {
        let abiVersion: UInt32
        let executablePath: String
        let prefixPath: String
        let workingDirectory: String
        let arguments: [String]
    }

    static func status() -> WinlatorWineRuntimeStatus {
        guard let symbols = resolve() else {
            return WinlatorWineRuntimeStatus(
                title: "Not installed",
                detail: "No compatible embedded WineRuntime.framework with the required ARM64 in-process ABI exports is available. The app has not bundled a Wine engine."
            )
        }
        guard symbols.version == expectedABI else {
            return WinlatorWineRuntimeStatus(
                title: "ABI mismatch",
                detail: "Wine adapter ABI \(symbols.version) is incompatible; expected ABI \(expectedABI)."
            )
        }
        return WinlatorWineRuntimeStatus(
            title: "ARM64 runtime ready",
            detail: "Embedded Wine framework loaded and both ABI entry points validated. Windows execution is available only when this framework supplies the documented in-process implementation."
        )
    }

    static func launch(executableURL: URL, container: WinlatorContainer,
                       arguments: [String] = []) -> String {
        let ext = executableURL.pathExtension.lowercased()
        guard ext == "exe" || ext == "msi" else {
            return "Launch blocked: only .EXE and .MSI files are supported."
        }
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            return "Launch failed: installer file is missing."
        }
        guard let symbols = resolve(), symbols.version == expectedABI else {
            return status().detail
        }

        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let root = support.appendingPathComponent(
                "Winlator/Containers/\(container.id.uuidString)", isDirectory: true
            )
            let prefix = root.appendingPathComponent("prefix", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: prefix.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return "Launch blocked: prepare the Wine prefix before starting an app."
            }
            let request = LaunchRequest(
                abiVersion: expectedABI,
                executablePath: executableURL.path,
                prefixPath: prefix.path,
                workingDirectory: executableURL.deletingLastPathComponent().path,
                arguments: arguments
            )
            let payload = try JSONEncoder().encode(request)
            guard let json = String(data: payload, encoding: .utf8) else {
                return "Launch failed: could not encode the Wine launch request."
            }
            let run = unsafeBitCast(symbols.run, to: RunFunction.self)
            let result = json.withCString { run($0) }
            return result == 0
                ? "Wine runtime accepted the launch request for \(executableURL.lastPathComponent)."
                : "Wine runtime returned error code \(result)."
        } catch {
            return "Launch failed: \(error.localizedDescription)"
        }
    }

    private static func resolve() -> (version: UInt32, run: UnsafeMutableRawPointer)? {
        lock.lock()
        defer { lock.unlock() }

        if let handle = loadedHandle {
            return resolveSymbols(in: handle)
        }
        guard let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let frameworkURL = frameworks.appendingPathComponent("WineRuntime.framework", isDirectory: true)
        guard let info = NSDictionary(contentsOf: frameworkURL.appendingPathComponent("Info.plist")) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String,
              info["WinlatorWineRuntimeABI"] as? String == "ios-arm64-inprocess" else {
            return nil
        }
        let binaryURL = frameworkURL.appendingPathComponent(executable)
        guard containsArm64MachO(at: binaryURL),
              let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }
        loadedHandle = handle
        return resolveSymbols(in: handle)
    }

    private static func resolveSymbols(in handle: UnsafeMutableRawPointer)
        -> (version: UInt32, run: UnsafeMutableRawPointer)? {
        guard let versionPointer = dlsym(handle, versionSymbol),
              let runPointer = dlsym(handle, runSymbol) else { return nil }
        let versionFunction = unsafeBitCast(versionPointer, to: VersionFunction.self)
        return (versionFunction(), runPointer)
    }

    private static func containsArm64MachO(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), data.count >= 8 else { return false }
        let bytes = [UInt8](data.prefix(8))
        let magic = Array(bytes.prefix(4))
        let littleEndian: Bool
        if magic == [0xCF, 0xFA, 0xED, 0xFE] { littleEndian = true }
        else if magic == [0xFE, 0xED, 0xFA, 0xCF] { littleEndian = false }
        else { return false }
        let b = Array(bytes[4..<8])
        let cpu = littleEndian
            ? UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
            : (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        return cpu == 0x0100000C
    }
}
