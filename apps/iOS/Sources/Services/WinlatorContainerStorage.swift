import Foundation

enum WinlatorContainerStorage {
    static func createLayout(for container: WinlatorContainer) throws {
        let manager = FileManager.default
        let base = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let containersRoot = base.appendingPathComponent("Winlator/Containers", isDirectory: true)
        try manager.createDirectory(at: containersRoot, withIntermediateDirectories: true)
        let destination = containersRoot.appendingPathComponent(container.id.uuidString, isDirectory: true)
        guard !manager.fileExists(atPath: destination.path) else {
            throw ContainerStorageError.alreadyExists
        }

        let staging = containersRoot.appendingPathComponent(
            ".creating-\(container.id.uuidString)-\(UUID().uuidString)",
            isDirectory: true
        )
        var committed = false
        defer {
            if !committed { try? manager.removeItem(at: staging) }
        }

        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        let paths = [
            "rootfs",
            "prefix/drive_c/Windows",
            "prefix/drive_c/Program Files",
            "drive_c/Installers",
            "home",
            "tmp",
            "downloads",
            "logs",
            "config"
        ]
        for path in paths {
            try manager.createDirectory(
                at: staging.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let manifest: [String: String] = [
            "id": container.id.uuidString,
            "name": container.name,
            "rootfs": "empty-awaiting-runtime",
            "wine": "not-installed",
            "translation": "not-installed",
            "graphics": "not-configured"
        ]
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: staging.appendingPathComponent("container.json"), options: .atomic)
        try manager.moveItem(at: staging, to: destination)
        committed = true
    }
}

private enum ContainerStorageError: LocalizedError {
    case alreadyExists

    var errorDescription: String? {
        "A container with this identifier already exists. Existing container data was left untouched."
    }
}
