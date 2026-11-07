import Foundation
import Metal

struct WinlatorGraphicsRuntimeCheck {
    let title: String
    let detail: String
}

struct WinlatorGraphicsRuntimeStatus {
    let metal: WinlatorGraphicsRuntimeCheck
    let vulkan: WinlatorGraphicsRuntimeCheck
    let bridge: WinlatorGraphicsRuntimeCheck
}

/// Reports graphics components embedded in the app. This is detection only:
/// it does not translate DirectX commands or create a Vulkan-to-Metal device.
enum WinlatorGraphicsRuntimeStorage {
    static func status() -> WinlatorGraphicsRuntimeStatus {
        let metal = checkMetal()
        let vulkan = checkVulkan()
        let bridge: WinlatorGraphicsRuntimeCheck

        if metal.title == "Available" && vulkan.title == "ARM64 bundle detected" {
            bridge = WinlatorGraphicsRuntimeCheck(
                title: "Components detected",
                detail: "Metal and MoltenVK are present. A DirectX-to-Vulkan translation layer and a callable graphics adapter are still required; no Windows graphics commands are being translated."
            )
        } else {
            bridge = WinlatorGraphicsRuntimeCheck(
                title: "Not configured",
                detail: "The DirectX-to-Vulkan-to-Metal path is not active. It requires an embedded Vulkan implementation, a DirectX translation layer and an iOS-compatible adapter."
            )
        }

        return WinlatorGraphicsRuntimeStatus(metal: metal, vulkan: vulkan, bridge: bridge)
    }

    private static func checkMetal() -> WinlatorGraphicsRuntimeCheck {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return WinlatorGraphicsRuntimeCheck(
                title: "Unavailable",
                detail: "Metal did not return a default GPU device on this iOS device."
            )
        }
        return WinlatorGraphicsRuntimeCheck(
            title: "Available",
            detail: "Metal device: \(device.name). This confirms native GPU access, not Windows DirectX compatibility."
        )
    }

    private static func checkVulkan() -> WinlatorGraphicsRuntimeCheck {
        guard let frameworks = Bundle.main.privateFrameworksURL else {
            return WinlatorGraphicsRuntimeCheck(
                title: "Not installed",
                detail: "The app has no embedded Frameworks directory; MoltenVK.framework is not bundled."
            )
        }

        let framework = frameworks.appendingPathComponent("MoltenVK.framework", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: framework.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return WinlatorGraphicsRuntimeCheck(
                title: "Not installed",
                detail: "No embedded MoltenVK.framework was found. Vulkan is not bundled in this IPA."
            )
        }

        let infoURL = framework.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty else {
            return WinlatorGraphicsRuntimeCheck(
                title: "Invalid framework",
                detail: "MoltenVK is present but its bundle metadata or executable name is invalid."
            )
        }

        let binaryURL = framework.appendingPathComponent(executable)
        guard let binary = try? Data(contentsOf: binaryURL), containsArm64MachO(binary) else {
            return WinlatorGraphicsRuntimeCheck(
                title: "Incompatible binary",
                detail: "MoltenVK does not contain a recognized ARM64 Mach-O executable."
            )
        }

        let version = info["CFBundleShortVersionString"] as? String ?? "unknown version"
        return WinlatorGraphicsRuntimeCheck(
            title: "ARM64 bundle detected",
            detail: "MoltenVK \(version) passed bundle and ARM64 checks. Vulkan device creation and validation are not yet wired into the app."
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
