import Foundation

struct WinlatorTranslationRuntimeCheck {
    let title: String
    let detail: String
}

struct WinlatorCPUTranslationRuntimeStatus {
    let box64: WinlatorTranslationRuntimeCheck
    let box86: WinlatorTranslationRuntimeCheck
}

/// Detects app-bundled, signed translation frameworks. Detection is deliberately
/// separate from execution: no guest process is started by this service.
enum WinlatorCPUTranslationRuntimeStorage {
    static func status() -> WinlatorCPUTranslationRuntimeStatus {
        WinlatorCPUTranslationRuntimeStatus(
            box64: check(frameworkName: "Box64Runtime", expectedABI: "ios-arm64-inprocess"),
            box86: check(frameworkName: "Box86Runtime", expectedABI: "ios-arm64-inprocess")
        )
    }

    private static func check(frameworkName: String, expectedABI: String) -> WinlatorTranslationRuntimeCheck {
        guard let frameworks = Bundle.main.privateFrameworksURL else {
            return WinlatorTranslationRuntimeCheck(
                title: "Not installed",
                detail: "The app has no embedded Frameworks directory; \(frameworkName).framework is not available."
            )
        }

        let framework = frameworks.appendingPathComponent("\(frameworkName).framework", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: framework.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return WinlatorTranslationRuntimeCheck(
                title: "Not installed",
                detail: "No embedded \(frameworkName).framework was found. The translation engine is not bundled in this IPA."
            )
        }

        let infoURL = framework.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty else {
            return WinlatorTranslationRuntimeCheck(
                title: "Invalid framework",
                detail: "\(frameworkName) is present but its bundle metadata or executable name is invalid."
            )
        }

        let executableURL = framework.appendingPathComponent(executable)
        guard let binary = try? Data(contentsOf: executableURL),
              containsArm64MachO(binary) else {
            return WinlatorTranslationRuntimeCheck(
                title: "Incompatible binary",
                detail: "\(frameworkName) does not contain a recognized ARM64 Mach-O executable."
            )
        }

        let abi = info["WinlatorTranslationRuntimeABI"] as? String ?? "unspecified"
        guard abi == expectedABI else {
            return WinlatorTranslationRuntimeCheck(
                title: "ABI mismatch",
                detail: "\(frameworkName) reports ABI '\(abi)'; expected \(expectedABI)."
            )
        }

        let version = info["WinlatorTranslationRuntimeVersion"] as? String ?? "unknown version"
        return WinlatorTranslationRuntimeCheck(
            title: "ARM64 bundle detected",
            detail: "\(frameworkName) \(version) passed bundle, architecture and ABI checks. Guest instruction translation is not enabled until its runtime adapter is integrated."
        )
    }

    private static func containsArm64MachO(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let bytes = [UInt8](data.prefix(8))
        let magic = Array(bytes.prefix(4))
        let littleEndian: Bool
        if magic == [0xCF, 0xFA, 0xED, 0xFE] { littleEndian = true }
        else if magic == [0xFE, 0xED, 0xFA, 0xCF] { littleEndian = false }
        else { return false }

        let cpu = bytes[4..<8]
        let cpuType: UInt32
        if littleEndian {
            cpuType = UInt32(cpu[cpu.startIndex]) |
                (UInt32(cpu[cpu.startIndex + 1]) << 8) |
                (UInt32(cpu[cpu.startIndex + 2]) << 16) |
                (UInt32(cpu[cpu.startIndex + 3]) << 24)
        } else {
            cpuType = (UInt32(cpu[cpu.startIndex]) << 24) |
                (UInt32(cpu[cpu.startIndex + 1]) << 16) |
                (UInt32(cpu[cpu.startIndex + 2]) << 8) |
                UInt32(cpu[cpu.startIndex + 3])
        }
        return cpuType == 0x0100000C
    }
}
