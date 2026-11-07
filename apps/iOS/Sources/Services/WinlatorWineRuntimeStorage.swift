import Foundation

struct WinlatorWineRuntimeStatus {
    let title: String
    let detail: String
}

enum WinlatorWineRuntimeStorage {
    static func status() -> WinlatorWineRuntimeStatus {
        guard let frameworkURL = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("WineRuntime.framework", isDirectory: true) else {
            return WinlatorWineRuntimeStatus(
                title: "Not installed",
                detail: "No embedded WineRuntime.framework is present. A normal iOS app cannot launch an arbitrary Wine executable from its Documents or Application Support folder; the runtime must be built and signed as part of the app."
            )
        }

        let infoURL = frameworkURL.appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              let executableName = info["CFBundleExecutable"] as? String else {
            return WinlatorWineRuntimeStatus(title: "Invalid bundle", detail: "Wine runtime framework metadata is missing.")
        }
        let executableURL = frameworkURL.appendingPathComponent(executableName)
        guard let data = try? Data(contentsOf: executableURL), Self.containsArm64MachO(data) else {
            return WinlatorWineRuntimeStatus(title: "Incompatible runtime", detail: "The embedded framework does not contain a recognized ARM64 Mach-O executable.")
        }
        let version = info["WinlatorWineRuntimeVersion"] as? String ?? "unknown version"
        let abi = info["WinlatorWineRuntimeABI"] as? String ?? "unspecified ABI"
        guard abi == "ios-arm64-inprocess" else {
            return WinlatorWineRuntimeStatus(title: "ABI mismatch", detail: "Runtime \(version) has ABI '\(abi)'; expected ios-arm64-inprocess.")
        }
        return WinlatorWineRuntimeStatus(title: "ARM64 bundle detected", detail: "Wine runtime \(version) passed bundle and ARM64 checks. The app still needs a runtime adapter to call its exported in-process API.")
    }

    private static func containsArm64MachO(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let bytes = [UInt8](data.prefix(8))
        let magic = Array(bytes.prefix(4))
        let isLittleEndian: Bool
        if magic == [0xCF, 0xFA, 0xED, 0xFE] { isLittleEndian = true }
        else if magic == [0xFE, 0xED, 0xFA, 0xCF] { isLittleEndian = false }
        else { return false }
        let cpuBytes = Array(bytes[4..<8])
        let cpuType: UInt32
        if isLittleEndian {
            cpuType = UInt32(cpuBytes[0]) | (UInt32(cpuBytes[1]) << 8) |
                (UInt32(cpuBytes[2]) << 16) | (UInt32(cpuBytes[3]) << 24)
        } else {
            cpuType = (UInt32(cpuBytes[0]) << 24) | (UInt32(cpuBytes[1]) << 16) |
                (UInt32(cpuBytes[2]) << 8) | UInt32(cpuBytes[3])
        }
        return cpuType == 0x0100000C
    }
}
