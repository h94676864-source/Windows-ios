import Foundation

enum WinlatorWinePrefixStorage {
    private static let prefixVersion = 1

    static func status(for container: WinlatorContainer) -> String {
        do {
            let root = try prefixURL(for: container)
            let metadataURL = root.appendingPathComponent("winlator-prefix.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path),
                  let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  metadata["state"] as? String == "prepared-awaiting-wineboot" else {
                return "Not prepared"
            }
            return "Prepared • awaiting wineboot"
        } catch {
            return "Unavailable"
        }
    }

    @discardableResult
    static func prepare(for container: WinlatorContainer) throws -> String {
        let manager = FileManager.default
        let prefix = try prefixURL(for: container)
        let parent = prefix.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)

        let staging = parent.appendingPathComponent("prefix-staging-\(UUID().uuidString)", isDirectory: true)
        let backup = parent.appendingPathComponent("prefix-previous", isDirectory: true)
        do {
            let directories = [
                "drive_c", "drive_c/Windows", "drive_c/Windows/System32",
                "drive_c/Program Files", "drive_c/Program Files (x86)",
                "drive_c/users", "drive_c/users/Public", "drive_c/users/Default",
                "dosdevices", "dosdevices/z:", "temp"
            ]
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            for path in directories {
                try manager.createDirectory(at: staging.appendingPathComponent(path, isDirectory: true),
                                            withIntermediateDirectories: true)
            }

            let metadata: [String: Any] = [
                "formatVersion": prefixVersion,
                "containerID": container.id.uuidString,
                "containerName": container.name,
                "architecture": container.architecture.lowercased(),
                "windowsVersion": container.windowsVersion,
                "state": "prepared-awaiting-wineboot",
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "note": "Directory skeleton only; run wineboot with a compatible Wine runtime to create a functional prefix."
            ]
            let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: staging.appendingPathComponent("winlator-prefix.json"), options: .atomic)

            if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
            if manager.fileExists(atPath: prefix.path) { try manager.moveItem(at: prefix, to: backup) }
            do {
                try manager.moveItem(at: staging, to: prefix)
                if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
            } catch {
                if manager.fileExists(atPath: backup.path) { try? manager.moveItem(at: backup, to: prefix) }
                throw error
            }
            return "Wine prefix directory layout prepared. It is not bootstrapped yet; wineboot must run after a compatible Wine runtime is integrated."
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    private static func prefixURL(for container: WinlatorContainer) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("Winlator/Containers/\(container.id.uuidString)/prefix", isDirectory: true)
    }
}
