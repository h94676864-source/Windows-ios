import Foundation

struct WinlatorInstallerRecord: Identifiable {
    let id: String
    let name: String
    let fileURL: URL
    let byteCount: Int64
}

enum WinlatorInstallerStorage {
    static func list(for container: WinlatorContainer) throws -> [WinlatorInstallerRecord] {
        let folder = try installerDirectory(for: container)
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return urls.filter { ["exe", "msi"].contains($0.pathExtension.lowercased()) }.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return WinlatorInstallerRecord(
                id: url.lastPathComponent, name: url.deletingPathExtension().lastPathComponent,
                fileURL: url, byteCount: Int64(values?.fileSize ?? 0)
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    static func importInstaller(from source: URL, for container: WinlatorContainer) throws -> WinlatorInstallerRecord {
        let ext = source.pathExtension.lowercased()
        guard ext == "exe" || ext == "msi" else { throw InstallerStorageError.unsupportedType }

        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }

        let inspection = try WinlatorInstallerInspector.inspect(source)
        guard inspection.isStructurallyValid else {
            throw InstallerStorageError.invalidInstaller(inspection.details.joined(separator: " "))
        }

        let folder = try installerDirectory(for: container)
        for existing in try list(for: container) {
            guard let existingInspection = try? WinlatorInstallerInspector.inspect(existing.fileURL) else { continue }
            if existingInspection.sha256 == inspection.sha256 {
                throw InstallerStorageError.duplicateContent(existing.fileURL.lastPathComponent)
            }
        }

        let destination = uniqueDestination(for: source.lastPathComponent, in: folder)
        try FileManager.default.copyItem(at: source, to: destination)
        do {
            try WinlatorInstallerIntegrityStore.record(
                inspection: inspection, filename: destination.lastPathComponent, container: container
            )
            let values = try destination.resourceValues(forKeys: [.fileSizeKey])
            return WinlatorInstallerRecord(
                id: destination.lastPathComponent, name: destination.deletingPathExtension().lastPathComponent,
                fileURL: destination, byteCount: Int64(values.fileSize ?? 0)
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func remove(_ record: WinlatorInstallerRecord, for container: WinlatorContainer) throws {
        let folder = try installerDirectory(for: container).standardizedFileURL
        let target = record.fileURL.standardizedFileURL
        guard target.deletingLastPathComponent() == folder else { throw InstallerStorageError.invalidLocation }
        try FileManager.default.removeItem(at: target)
        try WinlatorInstallerIntegrityStore.remove(filename: target.lastPathComponent, container: container)
    }

    private static func installerDirectory(for container: WinlatorContainer) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent(
            "Winlator/Containers/\(container.id.uuidString)/drive_c/Installers", isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.standardizedFileURL
    }

    private static func uniqueDestination(for filename: String, in folder: URL) -> URL {
        let manager = FileManager.default
        let original = URL(fileURLWithPath: filename)
        var candidate = folder.appendingPathComponent(filename)
        var index = 2
        while manager.fileExists(atPath: candidate.path) {
            let renamed = original.deletingPathExtension().lastPathComponent + " (\(index))." + original.pathExtension
            candidate = folder.appendingPathComponent(renamed)
            index += 1
        }
        return candidate
    }
}

private enum InstallerStorageError: LocalizedError {
    case unsupportedType
    case invalidLocation
    case invalidInstaller(String)
    case duplicateContent(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "Only .EXE and .MSI installers can be imported."
        case .invalidLocation:
            return "The selected installer is outside this container's installer folder."
        case .invalidInstaller(let detail):
            return "Installer validation failed. \(detail)"
        case .duplicateContent(let filename):
            return "This installer has already been imported as \(filename)."
        }
    }
}
