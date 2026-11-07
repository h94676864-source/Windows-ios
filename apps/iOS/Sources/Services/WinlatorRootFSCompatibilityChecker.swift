import Foundation

struct WinlatorRootFSCompatibilityReport {
    let title: String
    let checks: [String]
    let isCompatible: Bool

    var message: String {
        ([title] + checks + [
            "",
            "This is a structural check only. It does not execute Linux binaries or prove that Wine/Box64 can run on iOS."
        ]).joined(separator: "\n")
    }
}

enum WinlatorRootFSCompatibilityChecker {
    static func inspect(for container: WinlatorContainer) -> WinlatorRootFSCompatibilityReport {
        let manager = FileManager.default
        do {
            let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
            let root = support.appendingPathComponent(
                "Winlator/Containers/\(container.id.uuidString)/rootfs", isDirectory: true
            )
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return WinlatorRootFSCompatibilityReport(
                    title: "RootFS not imported",
                    checks: ["✗ Container rootfs directory is missing."],
                    isCompatible: false
                )
            }

            let requiredDirectories = ["bin", "etc", "usr"]
            var checks: [String] = []
            var requiredDirectoriesPresent = true
            for name in requiredDirectories {
                var childIsDirectory: ObjCBool = false
                let exists = manager.fileExists(
                    atPath: root.appendingPathComponent(name, isDirectory: true).path,
                    isDirectory: &childIsDirectory
                ) && childIsDirectory.boolValue
                checks.append("\(exists ? "✓" : "✗") Required directory: /\(name)")
                requiredDirectoriesPresent = requiredDirectoriesPresent && exists
            }

            let shellCandidates = ["bin/sh", "usr/bin/sh", "bin/bash", "usr/bin/bash"]
            let hasShell = shellCandidates.contains {
                manager.isExecutableFile(atPath: root.appendingPathComponent($0).path)
            }
            checks.append("\(hasShell ? "✓" : "✗") Executable shell found")

            let releaseCandidates = ["etc/os-release", "etc/alpine-release", "etc/debian_version"]
            let hasReleaseInfo = releaseCandidates.contains {
                manager.fileExists(atPath: root.appendingPathComponent($0).path)
            }
            checks.append("\(hasReleaseInfo ? "✓" : "•") Distribution release metadata")

            let arm64Candidates = [
                "bin/sh", "usr/bin/env", "usr/bin/uname",
                "lib/ld-linux-aarch64.so.1",
                "lib/aarch64-linux-gnu/ld-linux-aarch64.so.1",
                "usr/lib/ld-linux-aarch64.so.1"
            ]
            let arm64Binary = arm64Candidates.first {
                isAArch64ELF(at: root.appendingPathComponent($0))
            }
            checks.append("\(arm64Binary == nil ? "✗" : "✓") 64-bit ARM Linux ELF binary\(arm64Binary.map { ": /\($0)" } ?? "")")

            let compatible = requiredDirectoriesPresent && hasShell && arm64Binary != nil
            let title = compatible ? "Basic ARM64 RootFS checks passed" : "RootFS needs attention"
            return WinlatorRootFSCompatibilityReport(title: title, checks: checks, isCompatible: compatible)
        } catch {
            return WinlatorRootFSCompatibilityReport(
                title: "RootFS check failed",
                checks: ["✗ \(error.localizedDescription)"],
                isCompatible: false
            )
        }
    }

    private static func isAArch64ELF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 20), header.count >= 20 else {
            return false
        }
        let bytes = [UInt8](header)
        guard bytes[0] == 0x7F, bytes[1] == 0x45, bytes[2] == 0x4C, bytes[3] == 0x46 else {
            return false
        }
        // ELFCLASS64, little-endian, and e_machine == EM_AARCH64 (183).
        return bytes[4] == 2 && bytes[5] == 1 && bytes[18] == 183 && bytes[19] == 0
    }
}
