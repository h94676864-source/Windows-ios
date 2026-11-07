import Foundation

/// Routes installer launches through the embedded, signed Wine framework ABI.
/// No subprocess or shell execution is attempted by the iOS app itself.
enum WinlatorWineExecutionBridge {
    static func launch(executableURL: URL, container: WinlatorContainer) -> String {
        let manager = FileManager.default
        guard manager.fileExists(atPath: executableURL.path) else {
            return "Launch failed: the imported installer file is missing."
        }
        let fileExtension = executableURL.pathExtension.lowercased()
        guard fileExtension == "exe" || fileExtension == "msi" else {
            return "Launch blocked: only imported .EXE and .MSI files are supported."
        }

        do {
            let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
            let root = support.appendingPathComponent(
                "Winlator/Containers/\(container.id.uuidString)", isDirectory: true
            )
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return "Launch blocked: selected container storage is missing. Recreate the container."
            }
        } catch {
            return "Launch preflight failed: \(error.localizedDescription)"
        }

        return WinlatorWineRuntimeAdapter.launch(executableURL: executableURL, container: container)
    }
}
