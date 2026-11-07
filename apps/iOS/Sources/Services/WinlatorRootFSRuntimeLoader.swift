import Foundation

/// Builds a validated launch context for a future in-process Linux runtime.
/// It deliberately does not attempt fork/exec or execute ELF binaries on iOS.
struct WinlatorRootFSRuntimeContext {
    let rootURL: URL
    let shellURL: URL
    let libraryDirectories: [URL]
    let environment: [String: String]
}

enum WinlatorRootFSRuntimeLoader {
    static func prepare(for container: WinlatorContainer) throws -> WinlatorRootFSRuntimeContext {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let containerRoot = support.appendingPathComponent(
            "Winlator/Containers/\(container.id.uuidString)", isDirectory: true
        ).standardizedFileURL
        let root = containerRoot.appendingPathComponent("rootfs", isDirectory: true).standardizedFileURL
        let manager = FileManager.default

        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RootFSRuntimeError.missingRootFS
        }
        for name in ["bin", "etc", "usr"] {
            var childIsDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &childIsDirectory),
                  childIsDirectory.boolValue else {
                throw RootFSRuntimeError.missingDirectory(name)
            }
        }

        let shells = ["bin/sh", "usr/bin/sh", "bin/bash", "usr/bin/bash"]
        guard let shell = shells.map({ root.appendingPathComponent($0) })
            .first(where: { manager.isExecutableFile(atPath: $0.path) && isAArch64ELF($0) }) else {
            throw RootFSRuntimeError.noArm64Shell
        }

        let libraryCandidates = ["lib", "lib64", "usr/lib", "usr/local/lib"]
            .map { root.appendingPathComponent($0, isDirectory: true) }
            .filter { manager.fileExists(atPath: $0.path) }
        let home = containerRoot.appendingPathComponent("home", isDirectory: true)
        let temporary = containerRoot.appendingPathComponent("tmp", isDirectory: true)
        try manager.createDirectory(at: home, withIntermediateDirectories: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)

        let libraryPath = libraryCandidates.map(\.path).joined(separator: ":")
        let environment = [
            "HOME": home.path,
            "TMPDIR": temporary.path,
            "PATH": [root.appendingPathComponent("usr/bin").path,
                     root.appendingPathComponent("bin").path].joined(separator: ":"),
            "LD_LIBRARY_PATH": libraryPath,
            "LANG": "C.UTF-8",
            "WINLATOR_ROOTFS": root.path
        ]
        return WinlatorRootFSRuntimeContext(
            rootURL: root, shellURL: shell,
            libraryDirectories: libraryCandidates, environment: environment
        )
    }

    private static func isAArch64ELF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 20), data.count >= 20 else { return false }
        let bytes = [UInt8](data)
        return bytes[0...3].elementsEqual([0x7F, 0x45, 0x4C, 0x46]) &&
            bytes[4] == 2 && bytes[5] == 1 && bytes[18] == 183 && bytes[19] == 0
    }
}

private enum RootFSRuntimeError: LocalizedError {
    case missingRootFS
    case missingDirectory(String)
    case noArm64Shell

    var errorDescription: String? {
        switch self {
        case .missingRootFS:
            return "RootFS runtime setup failed: import a Linux root filesystem first."
        case .missingDirectory(let name):
            return "RootFS runtime setup failed: /\(name) is missing or is not a directory."
        case .noArm64Shell:
            return "RootFS runtime setup failed: no executable ARM64 Linux ELF shell was found."
        }
    }
}
