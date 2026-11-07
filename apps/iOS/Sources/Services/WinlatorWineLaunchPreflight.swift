import Foundation

struct WinlatorWineLaunchPreflightReport {
    let canSubmitToRuntime: Bool
    let checks: [String]

    var message: String { checks.joined(separator: "\n") }
}

/// Validates launch inputs. Passing does not imply a Wine engine is installed.
enum WinlatorWineLaunchPreflight {
    static func inspect(executableURL: URL, container: WinlatorContainer) -> WinlatorWineLaunchPreflightReport {
        let manager = FileManager.default
        var checks: [String] = []
        var valid = true

        let ext = executableURL.pathExtension.lowercased()
        let supported = ext == "exe" || ext == "msi"
        checks.append("\(supported ? "✓" : "✗") Installer type (.EXE/.MSI)")
        valid = valid && supported

        do {
            let inspection = try WinlatorInstallerInspector.inspect(executableURL)
            checks.append("✓ Installer structure: \(inspection.format)")
            checks.append("✓ Detected architecture: \(inspection.architecture)")
            checks.append("✓ SHA-256: \(inspection.sha256)")
            if !inspection.isStructurallyValid {
                checks.append("✗ Installer structure validation failed")
                valid = false
            }
        } catch {
            checks.append("✗ Installer inspection: \(error.localizedDescription)")
            valid = false
        }

        do {
            let isManaged = try WinlatorInstallerIntegrityStore.verifyIfManaged(executableURL, container: container)
            if isManaged {
                checks.append("✓ Container installer integrity manifest")
            } else {
                checks.append("— File is outside the managed container installer folder; manifest check skipped")
            }
        } catch {
            checks.append("✗ Installer integrity: \(error.localizedDescription)")
            valid = false
        }

        let attributes = try? manager.attributesOfItem(atPath: executableURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let regular = (attributes?[.type] as? FileAttributeType) == .typeRegular
        let filePresent = manager.fileExists(atPath: executableURL.path) && regular && size > 0
        checks.append("\(filePresent ? "✓" : "✗") Installer exists, is a regular file and is not empty")
        valid = valid && filePresent

        do {
            let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
            let root = support.appendingPathComponent(
                "Winlator/Containers/\(container.id.uuidString)", isDirectory: true
            )
            let prefix = root.appendingPathComponent("prefix", isDirectory: true)
            var isDirectory: ObjCBool = false
            let prefixReady = manager.fileExists(atPath: prefix.path, isDirectory: &isDirectory) && isDirectory.boolValue
            checks.append("\(prefixReady ? "✓" : "✗") Container Wine prefix directory")
            valid = valid && prefixReady

            if prefixReady {
                let metadataURL = prefix.appendingPathComponent("winlator-prefix.json")
                if manager.fileExists(atPath: metadataURL.path) {
                    let data = try Data(contentsOf: metadataURL)
                    guard let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        checks.append("✗ Prefix metadata is invalid")
                        return WinlatorWineLaunchPreflightReport(canSubmitToRuntime: false, checks: checks)
                    }
                    let matches = (metadata["containerID"] as? String) == container.id.uuidString
                    checks.append("\(matches ? "✓" : "✗") Prefix belongs to selected container")
                    valid = valid && matches
                } else {
                    checks.append("✗ Prefix metadata is absent; prepare the prefix first")
                    valid = false
                }
            }
        } catch {
            checks.append("✗ Container storage check: \(error.localizedDescription)")
            valid = false
        }

        do {
            _ = try WinlatorRootFSRuntimeLoader.prepare(for: container)
            checks.append("✓ ARM64 RootFS runtime layout")
        } catch {
            checks.append("✗ ARM64 RootFS: \(error.localizedDescription)")
            valid = false
        }

        let runtime = WinlatorWineRuntimeAdapter.status()
        let runtimeReady = runtime.title == "ARM64 runtime ready"
        checks.append("\(runtimeReady ? "✓" : "✗") Wine runtime: \(runtime.title)")
        valid = valid && runtimeReady

        return WinlatorWineLaunchPreflightReport(canSubmitToRuntime: valid, checks: checks)
    }
}
