import Foundation

enum WinlatorWinePrefixStorage {
    private static let prefixVersion = 2

    static func status(for container: WinlatorContainer) -> String {
        do {
            let root = try prefixURL(for: container)
            let metadataURL = root.appendingPathComponent("winlator-prefix.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path),
                  let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return FileManager.default.fileExists(atPath: root.path) ? "Existing data • metadata needs repair" : "Not prepared"
            }
            if let storedID = metadata["containerID"] as? String,
               storedID != container.id.uuidString {
                return "Metadata belongs to another container"
            }
            let state = metadata["state"] as? String ?? "unknown"
            if state == "prepared-awaiting-wineboot" || state == "existing-prefix-preserved-needs-wineboot" {
                return "Prepared • awaiting wineboot"
            }
            return "Present • \(state)"
        } catch {
            return "Unavailable"
        }
    }

    @discardableResult
    static func prepare(for container: WinlatorContainer) throws -> String {
        let manager = FileManager.default
        let prefix = try prefixURL(for: container)
        try manager.createDirectory(at: prefix, withIntermediateDirectories: true)

        let metadataURL = prefix.appendingPathComponent("winlator-prefix.json")
        var metadata: [String: Any] = [:]
        let prefixAlreadyExisted = manager.contentsOfDirectory(atPath: prefix.path).isEmpty == false

        if manager.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw PrefixError.invalidMetadata
            }
            if let storedID = existing["containerID"] as? String,
               storedID != container.id.uuidString {
                throw PrefixError.containerMismatch
            }
            metadata = existing
        }

        // Create only missing directories. Never replace the prefix directory:
        // installed applications, registry files and user data remain untouched.
        let directories = [
            "drive_c", "drive_c/Windows", "drive_c/Windows/System32",
            "drive_c/Program Files", "drive_c/Program Files (x86)",
            "drive_c/users", "drive_c/users/Public", "drive_c/users/Default",
            "dosdevices", "dosdevices/z:", "temp"
        ]
        for path in directories {
            try manager.createDirectory(
                at: prefix.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let now = ISO8601DateFormatter().string(from: Date())
        metadata["formatVersion"] = prefixVersion
        metadata["containerID"] = container.id.uuidString
        metadata["containerName"] = container.name
        metadata["architecture"] = container.architecture.lowercased()
        metadata["windowsVersion"] = container.windowsVersion
        metadata["state"] = "existing-prefix-preserved-needs-wineboot"
        if metadata["createdAt"] == nil {
            metadata["createdAt"] = now
        }
        metadata["updatedAt"] = now
        metadata["note"] = "Prefix data is preserved. Directory repair is non-destructive; a compatible Wine runtime must run wineboot before Windows applications can execute."

        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: metadataURL, options: .atomic)

        if prefixAlreadyExisted {
            return "Prefix upgraded safely. Existing files and installed data were preserved; missing folders were added. Wineboot is still required."
        }
        return "Wine prefix layout created. It is not bootstrapped yet; wineboot is required after a compatible Wine runtime is integrated."
    }

    private static func prefixURL(for container: WinlatorContainer) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("Winlator/Containers/\(container.id.uuidString)/prefix", isDirectory: true)
    }
}

private enum PrefixError: LocalizedError {
    case invalidMetadata
    case containerMismatch

    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            return "The prefix metadata is invalid. Existing prefix files were left untouched."
        case .containerMismatch:
            return "This prefix belongs to a different container. No files were changed."
        }
    }
}
