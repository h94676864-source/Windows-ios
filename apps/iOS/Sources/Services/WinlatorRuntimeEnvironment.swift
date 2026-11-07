import Foundation

struct WinlatorEnvironmentItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let isHealthy: Bool
}

struct WinlatorEnvironmentReport {
    let items: [WinlatorEnvironmentItem]

    var healthyCount: Int { items.filter(\.isHealthy).count }

    var summary: String {
        let lines = items.map {
            "\($0.isHealthy ? "✓" : "⚠") \($0.title): \($0.value) — \($0.detail)"
        }
        return "Device / container environment: \(healthyCount)/\(items.count) checks healthy\n"
            + lines.joined(separator: "\n")
    }
}

/// Read-only diagnostics for the supported iOS 18.5 / ARM64 device profile.
/// It never attempts to change entitlements, bypass iOS process controls or launch guest code.
enum WinlatorRuntimeEnvironment {
    static func inspect(for container: WinlatorContainer) -> WinlatorEnvironmentReport {
        let process = ProcessInfo.processInfo
        var items: [WinlatorEnvironmentItem] = []

        let version = process.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let supportedOS = version.majorVersion > 18 ||
            (version.majorVersion == 18 && version.minorVersion >= 5)
        items.append(WinlatorEnvironmentItem(
            id: "ios-version",
            title: "iOS compatibility",
            value: versionString,
            detail: supportedOS ? "Meets the fixed iOS 18.5 minimum." : "This build profile requires iOS 18.5 or later.",
            isHealthy: supportedOS
        ))

        #if arch(arm64)
        items.append(WinlatorEnvironmentItem(
            id: "cpu-architecture", title: "Host architecture", value: "ARM64",
            detail: "Native ARM64 process; guest x86/x64 translation still requires a real translation engine.",
            isHealthy: true
        ))
        #else
        items.append(WinlatorEnvironmentItem(
            id: "cpu-architecture", title: "Host architecture", value: "Unsupported",
            detail: "The app process is not compiled for ARM64.",
            isHealthy: false
        ))
        #endif

        let memoryGB = Double(process.physicalMemory) / 1_073_741_824
        items.append(WinlatorEnvironmentItem(
            id: "physical-memory", title: "Physical memory",
            value: String(format: "%.1f GB", memoryGB),
            detail: "Device RAM capacity. iOS controls per-process memory limits; this is not the amount currently free.",
            isHealthy: memoryGB >= 4
        ))

        let thermal: String
        let thermalHealthy: Bool
        switch process.thermalState {
        case .nominal:
            thermal = "Nominal"; thermalHealthy = true
        case .fair:
            thermal = "Fair"; thermalHealthy = true
        case .serious:
            thermal = "Serious"; thermalHealthy = false
        case .critical:
            thermal = "Critical"; thermalHealthy = false
        @unknown default:
            thermal = "Unknown"; thermalHealthy = false
        }
        items.append(WinlatorEnvironmentItem(
            id: "thermal-state", title: "Thermal state", value: thermal,
            detail: thermalHealthy ? "No serious thermal throttling reported." : "Heavy workloads may be throttled; allow the device to cool.",
            isHealthy: thermalHealthy
        ))

        let lowPower = process.isLowPowerModeEnabled
        items.append(WinlatorEnvironmentItem(
            id: "low-power", title: "Low Power Mode",
            value: lowPower ? "Enabled" : "Disabled",
            detail: lowPower ? "Long-running workloads may be reduced by iOS power management." : "Low Power Mode is not restricting performance.",
            isHealthy: !lowPower
        ))

        let storageItem = containerStorageItem(for: container)
        items.append(storageItem)

        return WinlatorEnvironmentReport(items: items)
    }

    private static func containerStorageItem(for container: WinlatorContainer) -> WinlatorEnvironmentItem {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let root = support.appendingPathComponent(
                "Winlator/Containers/\(container.id.uuidString)", isDirectory: true
            ).standardizedFileURL
            let values = try root.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                return WinlatorEnvironmentItem(
                    id: "container-storage", title: "Container storage", value: "Missing",
                    detail: "Container directory is missing; recreate or repair this container.",
                    isHealthy: false
                )
            }

            let capacity = try support.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let freeBytes = capacity.volumeAvailableCapacityForImportantUsage ?? -1
            let size = directorySize(at: root)
            let freeText = freeBytes >= 0 ? ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file) : "Unknown free space"
            let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            return WinlatorEnvironmentItem(
                id: "container-storage", title: "Container storage",
                value: sizeText,
                detail: "Container footprint; device available storage: \(freeText).",
                isHealthy: freeBytes < 0 || freeBytes >= 512 * 1_024 * 1_024
            )
        } catch {
            return WinlatorEnvironmentItem(
                id: "container-storage", title: "Container storage", value: "Unavailable",
                detail: error.localizedDescription, isHealthy: false
            )
        }
    }

    private static func directorySize(at root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
