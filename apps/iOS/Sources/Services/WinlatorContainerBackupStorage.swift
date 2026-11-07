import Foundation
import CryptoKit

enum WinlatorContainerBackupStorage {
    struct Backup: Identifiable {
        let id: String
        let containerName: String
        let createdAt: Date
        let fileCount: Int
    }

    private struct Manifest: Codable {
        let version: Int
        let backupID: String
        let sourceContainerID: String
        let containerName: String
        let createdAt: Date
        let files: [FileRecord]
    }

    private struct FileRecord: Codable {
        let path: String
        let byteCount: Int64
        let sha256: String
    }

    private static var manager: FileManager { .default }

    static func list() throws -> [Backup] {
        let root = try backupsRoot()
        let urls = try manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            guard url.pathExtension == "winlatorbackup" else { return nil }
            let manifestURL = url.appendingPathComponent("backup-manifest.json")
            guard manager.fileExists(atPath: manifestURL.path) else { return nil }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.version == 1, manifest.backupID == url.deletingPathExtension().lastPathComponent else {
                throw BackupError.invalidManifest
            }
            return Backup(
                id: manifest.backupID,
                containerName: manifest.containerName,
                createdAt: manifest.createdAt,
                fileCount: manifest.files.count
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func create(for container: WinlatorContainer) throws -> Backup {
        let containersRoot = try containerRoot()
        let source = containersRoot.appendingPathComponent(container.id.uuidString, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BackupError.containerMissing
        }

        let root = try backupsRoot()
        let backupID = UUID().uuidString
        let staging = root.appendingPathComponent(".creating-\(backupID)", isDirectory: true)
        let destination = root.appendingPathComponent("\(backupID).winlatorbackup", isDirectory: true)
        var committed = false
        defer { if !committed { try? manager.removeItem(at: staging) } }

        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        let payload = staging.appendingPathComponent("payload", isDirectory: true)
        try manager.copyItem(at: source, to: payload)
        let records = try fileRecords(in: payload)
        let manifest = Manifest(
            version: 1,
            backupID: backupID,
            sourceContainerID: container.id.uuidString,
            containerName: container.name,
            createdAt: Date(),
            files: records
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: staging.appendingPathComponent("backup-manifest.json"), options: .atomic)
        try manager.moveItem(at: staging, to: destination)
        committed = true
        return Backup(id: backupID, containerName: container.name, createdAt: manifest.createdAt, fileCount: records.count)
    }

    static func restore(_ backup: Backup, to container: WinlatorContainer) throws {
        let root = try backupsRoot()
        let backupFolder = root.appendingPathComponent("\(backup.id).winlatorbackup", isDirectory: true)
        let manifestURL = backupFolder.appendingPathComponent("backup-manifest.json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1, manifest.backupID == backup.id,
              manifest.files.count == backup.fileCount else {
            throw BackupError.invalidManifest
        }

        let payload = backupFolder.appendingPathComponent("payload", isDirectory: true)
        try verify(payload: payload, records: manifest.files)

        let containers = try containerRoot()
        let destination = containers.appendingPathComponent(container.id.uuidString, isDirectory: true)
        let staging = containers.appendingPathComponent(".restoring-\(UUID().uuidString)", isDirectory: true)
        let rollback = containers.appendingPathComponent(".rollback-\(UUID().uuidString)", isDirectory: true)
        var movedOriginal = false
        var installed = false
        defer {
            if !installed { try? manager.removeItem(at: staging) }
            if movedOriginal && !installed {
                if !manager.fileExists(atPath: destination.path) {
                    try? manager.moveItem(at: rollback, to: destination)
                }
            }
        }

        try manager.copyItem(at: payload, to: staging)
        if manager.fileExists(atPath: destination.path) {
            try manager.moveItem(at: destination, to: rollback)
            movedOriginal = true
        }
        do {
            try manager.moveItem(at: staging, to: destination)
            installed = true
        } catch {
            if movedOriginal {
                try? manager.moveItem(at: rollback, to: destination)
                movedOriginal = false
            }
            throw error
        }
        if movedOriginal { try? manager.removeItem(at: rollback) }
    }

    static func delete(_ backup: Backup) throws {
        let root = try backupsRoot()
        let target = root.appendingPathComponent("\(backup.id).winlatorbackup", isDirectory: true)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedTarget = target.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedTarget.deletingLastPathComponent() == resolvedRoot else {
            throw BackupError.invalidLocation
        }
        try manager.removeItem(at: target)
    }

    private static func verify(payload: URL, records: [FileRecord]) throws {
        let actual = try fileRecords(in: payload)
        guard actual.count == records.count else { throw BackupError.integrityFailure }
        let expectedByPath = Dictionary(uniqueKeysWithValues: records.map { ($0.path, $0) })
        for item in actual {
            guard let expected = expectedByPath[item.path],
                  item.byteCount == expected.byteCount,
                  item.sha256 == expected.sha256 else {
                throw BackupError.integrityFailure
            }
        }
    }

    private static func fileRecords(in directory: URL) throws -> [FileRecord] {
        guard manager.fileExists(atPath: directory.path) else { throw BackupError.invalidLocation }
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { throw BackupError.invalidLocation }

        var records: [FileRecord] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw BackupError.symbolicLinkNotAllowed }
            guard values.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(directory.path.count + 1))
            guard !relative.isEmpty,
                  !relative.hasPrefix("/"),
                  !relative.split(separator: "/").contains(".."),
                  !relative.contains("\\") else {
                throw BackupError.invalidLocation
            }
            let (digest, byteCount) = try hashFile(url)
            records.append(FileRecord(path: relative, byteCount: byteCount, sha256: digest))
        }
        return records.sorted { $0.path < $1.path }
    }

    private static func hashFile(_ url: URL) throws -> (String, Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, total)
    }

    private static func containerRoot() throws -> URL {
        let support = try manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("Winlator/Containers", isDirectory: true)
    }

    private static func backupsRoot() throws -> URL {
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("WinlatorBackups", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private enum BackupError: LocalizedError {
        case containerMissing
        case invalidManifest
        case integrityFailure
        case invalidLocation
        case symbolicLinkNotAllowed

        var errorDescription: String? {
            switch self {
            case .containerMissing: return "Container data was not found. Create the container before backing it up."
            case .invalidManifest: return "Backup manifest is invalid or unsupported."
            case .integrityFailure: return "Backup integrity verification failed. The container was not changed."
            case .invalidLocation: return "Backup contains an invalid or unsafe file path."
            case .symbolicLinkNotAllowed: return "Backup contains a symbolic link and was rejected."
            }
        }
    }
}
