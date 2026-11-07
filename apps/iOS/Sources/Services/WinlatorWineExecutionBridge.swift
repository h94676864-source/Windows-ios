import Foundation

/// Performs a safe launch preflight and reports whether an installed runtime can be invoked.
/// The current iOS target has no bundled Wine runtime adapter, so preflight never pretends
/// that an imported Windows executable has been started.
enum WinlatorWineExecutionBridge {
    static func preflight(executableURL: URL, container: WinlatorContainer?) -> String {
        let manager = FileManager.default
        guard manager.fileExists(atPath: executableURL.path) else {
            return "Launch failed: the imported installer file is missing."
        }
        let fileExtension = executableURL.pathExtension.lowercased()
        guard fileExtension == "exe" || fileExtension == "msi" else {
            return "Launch blocked: only imported .EXE and .MSI files are supported."
        }
        guard let container else {
            return "Launch blocked: select a Windows container first."
        }

        do {
            let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: false)
            let root = support.appendingPathComponent(
                "Winlator/Containers/\(container.id.uuidString)", isDirectory: true
            )
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return "Launch blocked: the selected container storage is missing. Recreate the container."
            }
        } catch {
            return "Launch preflight failed: \(error.localizedDescription)"
        }

        let runtime = WinlatorWineRuntimeStorage.status()
        guard runtime.title == "ARM64 bundle detected" else {
            return "Launch blocked — Wine runtime unavailable. \(runtime.detail)"
        }

        return "Preflight passed for \(executableURL.lastPathComponent) in \(container.name), but execution is not available yet: the app has no callable Wine runtime adapter. No Windows process was started."
    }
}
