import Foundation

enum WinlatorRootFSStorage {
    static func importRootFS(from sourceURL: URL, for container: WinlatorContainer) throws -> String {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RootFSError.notDirectory
        }

        let manager = FileManager.default
        let source = sourceURL.standardizedFileURL
        for required in ["bin", "etc", "usr"] {
            guard manager.fileExists(atPath: source.appendingPathComponent(required).path) else {
                throw RootFSError.invalidLayout(required)
            }
        }

        let base = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true)
        let containerRoot = base.appendingPathComponent("Winlator/Containers/\(container.id.uuidString)", isDirectory: true)
        let rootFS = containerRoot.appendingPathComponent("rootfs", isDirectory: true)
        try manager.createDirectory(at: containerRoot, withIntermediateDirectories: true)

        let staging = containerRoot.appendingPathComponent("rootfs-import-\(UUID().uuidString)", isDirectory: true)
        do {
            try manager.copyItem(at: source, to: staging)
            for required in ["bin", "etc", "usr"] {
                guard manager.fileExists(atPath: staging.appendingPathComponent(required).path) else {
                    throw RootFSError.invalidLayout(required)
                }
            }

            let backup = containerRoot.appendingPathComponent("rootfs-previous", isDirectory: true)
            if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
            if manager.fileExists(atPath: rootFS.path) { try manager.moveItem(at: rootFS, to: backup) }
            do {
                try manager.moveItem(at: staging, to: rootFS)
                if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
            } catch {
                if manager.fileExists(atPath: backup.path) {
                    try? manager.moveItem(at: backup, to: rootFS)
                }
                throw error
            }

            let manifestURL = containerRoot.appendingPathComponent("container.json")
            var manifest = (try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))) as? [String: Any] ?? [:]
            manifest["id"] = container.id.uuidString
            manifest["name"] = container.name
            manifest["rootfs"] = "imported-user-supplied"
            manifest["rootfsSourceName"] = sourceURL.lastPathComponent
            manifest["rootfsImportedAt"] = ISO8601DateFormatter().string(from: Date())
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: manifestURL, options: .atomic)
            return "RootFS imported and validated (bin, etc, usr). Linux binaries still need a compatible iOS execution layer."
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }
}

enum RootFSError: LocalizedError {
    case notDirectory
    case invalidLayout(String)

    var errorDescription: String? {
        switch self {
        case .notDirectory:
            return "Select an extracted Linux root filesystem folder."
        case .invalidLayout(let folder):
            return "RootFS is incomplete: required '\(folder)' directory was not found."
        }
    }
}
