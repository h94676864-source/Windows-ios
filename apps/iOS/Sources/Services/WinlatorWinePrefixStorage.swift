import Foundation

enum WinlatorWinePrefixStorage {
    private static let prefixVersion = 2

    static func status(for container: WinlatorContainer) -> String {
        do {
            let prefix = try prefixURL(for: container)
            try validateDirectoryChain(through: prefix, createMissing: false)
            let metadataURL = prefix.appendingPathComponent("winlator-prefix.json")
            guard let values = try? metadataURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  metadata["containerID"] as? String == container.id.uuidString else {
                return "Existing data • metadata missing, invalid, or belongs to another container"
            }
            let state = metadata["state"] as? String ?? "unknown"
            if state == "prepared-awaiting-wineboot" || state == "existing-prefix-preserved-needs-wineboot" {
                return "Prepared • awaiting wineboot"
            }
            return "Present • \(state)"
        } catch {
            return "Unavailable • \(error.localizedDescription)"
        }
    }

    @discardableResult
    static func prepare(for container: WinlatorContainer) throws -> String {
        let manager = FileManager.default
        let prefix = try prefixURL(for: container)
        try validateDirectoryChain(through: prefix, createMissing: true)

        let metadataURL = prefix.appendingPathComponent("winlator-prefix.json")
        var metadata: [String: Any] = [:]
        let prefixAlreadyExisted = (try manager.contentsOfDirectory(atPath: prefix.path)).contains {
            $0 != "winlator-prefix.json"
        }

        if manager.fileExists(atPath: metadataURL.path) {
            let values = try metadataURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw PrefixError.unsafeMetadata
            }
            let data = try Data(contentsOf: metadataURL)
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  existing["containerID"] as? String == container.id.uuidString else {
                throw PrefixError.containerMismatch
            }
            metadata = existing
        }

        // Create only missing directories, validating every existing path component first.
        let directories = [
            "drive_c", "drive_c/Windows", "drive_c/Windows/System32",
            "drive_c/Program Files", "drive_c/Program Files (x86)",
            "drive_c/users", "drive_c/users/Public", "drive_c/users/Default",
            "dosdevices", "dosdevices/z:", "temp"
        ]
        for relativePath in directories {
            let directory = prefix.appendingPathComponent(relativePath, isDirectory: true)
            try validateDirectoryChain(through: directory, createMissing: true)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        metadata["formatVersion"] = prefixVersion
        metadata["containerID"] = container.id.uuidString
        metadata["containerName"] = container.name
        metadata["architecture"] = container.architecture.lowercased()
        metadata["windowsVersion"] = container.windowsVersion
        metadata["state"] = "existing-prefix-preserved-needs-wineboot"
        if metadata["createdAt"] == nil { metadata["createdAt"] = now }
        metadata["updatedAt"] = now
        metadata["note"] = "Prefix data is preserved. Directory repair is non-destructive; a compatible Wine runtime must run wineboot before Windows applications can execute."

        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: metadataURL, options: .atomic)

        return prefixAlreadyExisted
            ? "Prefix upgraded safely. Existing files and installed data were preserved; missing folders were added. Wineboot is still required."
            : "Wine prefix layout created. It is not bootstrapped yet; wineboot is required after a compatible Wine runtime is integrated."
    }

    private static func prefixURL(for container: WinlatorContainer) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("Winlator/Containers/\(container.id.uuidString)/prefix", isDirectory: true)
    }

    /// Walks from Application Support to the requested directory. Existing symlinks and
    /// non-directory components are rejected before any child path is used.
    private static func validateDirectoryChain(through target: URL, createMissing: Bool) throws {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true).standardizedFileURL
        let target = target.standardizedFileURL
        let supportPath = support.path.hasSuffix("/") ? support.path : support.path + "/"
        guard target.path == support.path || target.path.hasPrefix(supportPath) else {
            throw PrefixError.pathEscapesApplicationSupport
        }

        let relative = String(target.path.dropFirst(support.path.count))
            .split(separator: "/").map(String.init)
        var current = support
        for component in relative {
            current.appendPathComponent(component, isDirectory: true)
            if manager.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw PrefixError.unsafeDirectory(current.lastPathComponent)
                }
            } else if createMissing {
                try manager.createDirectory(at: current, withIntermediateDirectories: false)
                let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw PrefixError.unsafeDirectory(current.lastPathComponent)
                }
            } else {
                throw PrefixError.missingDirectory(current.lastPathComponent)
            }
        }
    }
}

private enum PrefixError: LocalizedError {
    case invalidMetadata
    case containerMismatch
    case unsafeMetadata
    case pathEscapesApplicationSupport
    case unsafeDirectory(String)
    case missingDirectory(String)

    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            return "The prefix metadata is invalid. Existing prefix files were left untouched."
        case .containerMismatch:
            return "This prefix metadata is missing a valid matching container ID or belongs to another container. No files were changed."
        case .unsafeMetadata:
            return "Prefix metadata must be a regular non-symlink file. No files were changed."
        case .pathEscapesApplicationSupport:
            return "The Wine prefix path escapes the app's Application Support directory."
        case .unsafeDirectory(let name):
            return "Unsafe prefix path component '\(name)': expected a real directory, not a symlink or file."
        case .missingDirectory(let name):
            return "Required prefix directory '\(name)' is missing."
        }
    }
}
