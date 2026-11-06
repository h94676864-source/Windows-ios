import Foundation

enum WinlatorContainerStorage {
    static func createLayout(for container: WinlatorContainer) throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = base.appendingPathComponent("Winlator/Containers/\(container.id.uuidString)", isDirectory: true)
        let paths = ["rootfs", "prefix/drive_c/Windows", "prefix/drive_c/Program Files", "drive_c/Installers", "home", "tmp", "downloads", "logs", "config"]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for path in paths {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path, isDirectory: true), withIntermediateDirectories: true)
        }
        let manifest = ["id": container.id.uuidString, "name": container.name, "rootfs": "empty-awaiting-runtime", "wine": "not-installed", "translation": "not-installed", "graphics": "not-configured"]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("container.json"), options: .atomic)
    }
}
