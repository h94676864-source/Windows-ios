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
/// - exported int32_t winlator_wine_runtime_self_test(void)
///
/// The self-test must initialize/validate the in-process Wine core and return 0 only
/// when the runtime is callable. Merely loading the ABI symbols is not execution readiness.
/// The JSON request contains executablePath, prefixPath, workingDirectory and arguments.
/// The framework must execute Wine in-process; iOS does not provide fork/exec for app binaries.
enum WinlatorWineRuntimeAdapter {
    private static let expectedABI: UInt32 = 1
    private static let versionSymbol = "winlator_wine_abi_version"
    private static let runSymbol = "winlator_wine_run_json"
    private static let selfTestSymbol = "winlator_wine_runtime_self_test"
    private static let lock = NSLock()
    private static var loadedHandle: UnsafeMutableRawPointer?

    private typealias VersionFunction = @convention(c) () -> UInt32
    private typealias RunFunction = @convention(c) (UnsafePointer<CChar>?) -> Int32
    private typealias SelfTestFunction = @convention(c) () -> Int32

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
                title: "Not installed or incompatible",
                detail: "No compatible embedded WineRuntime.framework with ARM64 run, version and self-test exports is available. No Wine engine is bundled in this IPA."
            )
        }
        guard symbols.version == expectedABI else {
            return WinlatorWineRuntimeStatus(
                title: "ABI mismatch",
                detail: "Wine adapter ABI \(symbols.version) is incompatible; expected ABI \(expectedABI)."
            )
        }
        let selfTest = unsafeBitCast(symbols.selfTest, to: SelfTestFunction.self)
        let result = selfTest()
        guard result == 0 else {
            return WinlatorWineRuntimeStatus(
                title: "Runtime self-test failed",
                detail: "WineRuntime.framework loaded, but its in-process self-test returned \(result). Windows launch remains disabled."
            )
        }
        return WinlatorWineRuntimeStatus(
            title: "Runtime self-test passed",
            detail: "Wine ARM64 framework, ABI version, launch entry point and runtime self-test passed. App-level EXE compatibility still requires device testing."
        )
    }

    static func launch(executableURL: URL, container: WinlatorContainer,
                       arguments: [String] = []) -> String {
        let ext = executableURL.pathExtension.lowercased()
        guard ext == "exe" || ext == "msi" else {
            return "Launch blocked: only .EXE and .MSI files are supported."
        }
        let manager = FileManager.default
        let executableValues = try? executableURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let executableSize = (try? manager.attributesOfItem(atPath: executableURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard manager.fileExists(atPath: executableURL.path),
              executableValues?.isRegularFile == true,
              executableValues?.isSymbolicLink != true,
              executableSize > 0 else {
            return "Launch blocked: installer must be a non-empty regular file, not a symlink."
        }
        let runtimeStatus = status()
        guard runtimeStatus.title == "Runtime self-test passed",
              let symbols = resolve(), symbols.version == expectedABI else {
            return runtimeStatus.detail
        }

        do {
            let support = try manager.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let root = support.appendingPathComponent(
                "Winlator/Containers/\(container.id.uuidString)", isDirectory: true
            )
            let prefix = root.appendingPathComponent("prefix", isDirectory: true)
            let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let prefixValues = try? prefix.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true,
                  prefixValues?.isDirectory == true, prefixValues?.isSymbolicLink != true else {
                return "Launch blocked: container or Wine prefix is missing, invalid, or a symlink."
            }
            let metadataURL = prefix.appendingPathComponent("winlator-prefix.json")
            let metadataValues = try? metadataURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard metadataValues?.isRegularFile == true, metadataValues?.isSymbolicLink != true,
                  let metadataData = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                  metadata["containerID"] as? String == container.id.uuidString else {
                return "Launch blocked: Wine prefix metadata is missing, invalid, or belongs to another container."
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

    private static func resolve() -> (version: UInt32, run: UnsafeMutableRawPointer, selfTest: UnsafeMutableRawPointer)? {
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
        guard !executable.isEmpty, executable == URL(fileURLWithPath: executable).lastPathComponent,
              !executable.contains("..") else { return nil }
        let infoURL = frameworkURL.appendingPathComponent("Info.plist")
        let infoValues = try? infoURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let frameworkValues = try? frameworkURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        let binaryURL = frameworkURL.appendingPathComponent(executable)
        let binaryValues = try? binaryURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        let frameworkRoot = frameworks.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let resolvedFramework = frameworkURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedFramework.hasPrefix(frameworkRoot),
              infoValues?.isRegularFile == true,
              infoValues?.isSymbolicLink != true,
              frameworkValues?.isDirectory == true,
              frameworkValues?.isSymbolicLink != true,
              binaryValues?.isRegularFile == true,
              binaryValues?.isSymbolicLink != true,
              containsArm64MachO(at: binaryURL),
              let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }
        guard let resolved = resolveSymbols(in: handle) else {
            dlclose(handle)
            return nil
        }
        loadedHandle = handle
        return resolved
    }

    private static func resolveSymbols(in handle: UnsafeMutableRawPointer)
        -> (version: UInt32, run: UnsafeMutableRawPointer, selfTest: UnsafeMutableRawPointer)? {
        guard let versionPointer = dlsym(handle, versionSymbol),
              let runPointer = dlsym(handle, runSymbol),
              let selfTestPointer = dlsym(handle, selfTestSymbol) else { return nil }
        let versionFunction = unsafeBitCast(versionPointer, to: VersionFunction.self)
        return (versionFunction(), runPointer, selfTestPointer)
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
