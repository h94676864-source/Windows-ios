import Foundation

enum WinlatorInstallerIntegrityStore {
    private struct Manifest: Codable {
        var version: Int = 1
        var entries: [String: Entry] = [:]
    }

    private struct Entry: Codable {
        let sha256: String
        let byteCount: Int64
        let importedAt: Date
    }

    static func record(
        inspection: WinlatorInstallerInspection,
        filename: String,
        container: WinlatorContainer
    ) throws {
        var manifest = try load(for: container)
        manifest.entries[filename] = Entry(
            sha256: inspection.sha256,
            byteCount: inspection.byteCount,
            importedAt: Date()
        )
        try save(manifest, for: container)
    }

    static func remove(filename: String, container: WinlatorContainer) throws {
        var manifest = try load(for: container)
        manifest.entries.removeValue(forKey: filename)
        try save(manifest, for: container)
    }

    /// Returns false for files outside this container's managed Installers folder.
    /// Managed files without a manifest entry fail closed.
    @discardableResult
    static func verifyIfManaged(_ fileURL: URL, container: WinlatorContainer) throws -> Bool {
        let folder = try installerDirectory(for: container).standardizedFileURL
        let target = fileURL.standardizedFileURL
        guard target.deletingLastPathComponent() == folder else { return false }

        let manifest = try load(for: container)
        guard let expected = manifest.entries[target.lastPathComponent] else {
            throw IntegrityError.missingRecord
        }

        let actual = try WinlatorInstallerInspector.inspect(target)
        guard actual.isStructurallyValid,
              actual.byteCount == expected.byteCount,
              actual.sha256 == expected.sha256 else {
            throw IntegrityError.mismatch
        }
        return true
    }

    private static func load(for container: WinlatorContainer) throws -> Manifest {
        let url = try manifestURL(for: container)
        guard FileManager.default.fileExists(atPath: url.path) else { return Manifest() }
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.version == 1 else { throw IntegrityError.unsupportedManifest }
        for (filename, entry) in manifest.entries {
            let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
            guard !filename.isEmpty,
                  URL(fileURLWithPath: filename).lastPathComponent == filename,
                  !filename.contains("/"), !filename.contains("\\"),
                  ext == "exe" || ext == "msi",
                  entry.byteCount > 0,
                  entry.sha256.count == 64,
                  entry.sha256.unicodeScalars.allSatisfy({
                      (48...57).contains(Int($0.value)) || (97...102).contains(Int($0.value))
                  }) else {
                throw IntegrityError.invalidEntry
            }
        }
        return manifest
    }

    private static func save(_ manifest: Manifest, for container: WinlatorContainer) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(for: container), options: .atomic)
    }

    private static func manifestURL(for container: WinlatorContainer) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let config = support.appendingPathComponent(
            "Winlator/Containers/\(container.id.uuidString)/config", isDirectory: true
        )
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        return config.appendingPathComponent("installer-integrity.json")
    }

    private static func installerDirectory(for container: WinlatorContainer) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent(
            "Winlator/Containers/\(container.id.uuidString)/drive_c/Installers", isDirectory: true
        ).standardizedFileURL
    }

    private enum IntegrityError: LocalizedError {
        case missingRecord
        case mismatch
        case unsupportedManifest
        case invalidEntry

        var errorDescription: String? {
            switch self {
            case .missingRecord:
                return "Installer integrity record is missing. Re-import this installer to establish a trusted baseline."
            case .mismatch:
                return "Installer integrity check failed: file content or size changed after import."
            case .unsupportedManifest:
                return "Installer integrity manifest version is not supported."
            case .invalidEntry:
                return "Installer integrity manifest contains an invalid filename, size, or SHA-256 record."
            }
        }
    }
}
