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
        let manager = FileManager.default
        let support = try manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).standardizedFileURL
        let containerRoot = support.appendingPathComponent(
            "Winlator/Containers/\(container.id.uuidString)", isDirectory: true
        ).standardizedFileURL
        let root = containerRoot.appendingPathComponent("rootfs", isDirectory: true).standardizedFileURL

        try validateExistingDirectoryChain(from: support, through: containerRoot)
        try validateExistingDirectoryChain(from: support, through: root)

        // Standard Linux images commonly use /bin -> /usr/bin. Permit internal
        // symlinks, but reject any link whose resolved destination leaves RootFS.
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard isSameOrDescendant(resolvedRoot, of: support) == false,
              resolvedRoot.path.hasPrefix(support.path + "/") else {
            throw RootFSRuntimeError.unsafeRootFS
        }

        for name in ["bin", "etc", "usr"] {
            let candidate = root.appendingPathComponent(name, isDirectory: true)
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard isSameOrDescendant(resolved, of: resolvedRoot),
                  isDirectory(resolved) else {
                throw RootFSRuntimeError.invalidDirectory(name)
            }
        }

        let shellCandidates = ["bin/sh", "usr/bin/sh", "bin/bash", "usr/bin/bash"]
        guard let shell = shellCandidates
            .map({ root.appendingPathComponent($0) })
            .compactMap({ candidate -> URL? in
                let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
                guard isSameOrDescendant(resolved, of: resolvedRoot),
                      manager.isExecutableFile(atPath: resolved.path),
                      isAArch64ELF(resolved) else { return nil }
                return resolved
            }).first else {
            throw RootFSRuntimeError.noArm64Shell
        }

        let libraryNames = ["lib", "lib64", "usr/lib", "usr/local/lib"]
        var libraries: [URL] = []
        for name in libraryNames {
            let candidate = root.appendingPathComponent(name, isDirectory: true)
            guard manager.fileExists(atPath: candidate.path) else { continue }
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard isSameOrDescendant(resolved, of: resolvedRoot), isDirectory(resolved) else {
                throw RootFSRuntimeError.unsafeLibraryPath(name)
            }
            if !libraries.contains(resolved) { libraries.append(resolved) }
        }

        let home = containerRoot.appendingPathComponent("home", isDirectory: true)
        let temporary = containerRoot.appendingPathComponent("tmp", isDirectory: true)
        try createValidatedDirectory(home, support: support, containerRoot: containerRoot)
        try createValidatedDirectory(temporary, support: support, containerRoot: containerRoot)

        let environment = [
            "HOME": home.path,
            "TMPDIR": temporary.path,
            "PATH": [
                root.appendingPathComponent("usr/bin").path,
                root.appendingPathComponent("bin").path
            ].joined(separator: ":"),
            "LD_LIBRARY_PATH": libraries.map(\.path).joined(separator: ":"),
            "LANG": "C.UTF-8",
            "WINLATOR_ROOTFS": root.path
        ]
        return WinlatorRootFSRuntimeContext(
            rootURL: root, shellURL: shell,
            libraryDirectories: libraries, environment: environment
        )
    }

    private static func validateExistingDirectoryChain(from base: URL, through target: URL) throws {
        let manager = FileManager.default
        let basePath = base.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard targetPath == basePath || targetPath.hasPrefix(basePath + "/") else {
            throw RootFSRuntimeError.pathEscapesApplicationSupport
        }

        var current = base.standardizedFileURL
        let relative = String(targetPath.dropFirst(basePath.count))
            .split(separator: "/").map(String.init)
        for component in relative {
            current.appendPathComponent(component, isDirectory: true)
            let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw RootFSRuntimeError.unsafePathComponent(component)
            }
        }
        guard manager.fileExists(atPath: targetPath) else {
            throw RootFSRuntimeError.missingRootFS
        }
    }

    private static func createValidatedDirectory(
        _ target: URL, support: URL, containerRoot: URL
    ) throws {
        let manager = FileManager.default
        let supportPath = support.path
        let targetPath = target.standardizedFileURL.path
        guard targetPath.hasPrefix(supportPath + "/") else {
            throw RootFSRuntimeError.pathEscapesApplicationSupport
        }
        var current = support
        let components = String(targetPath.dropFirst(supportPath.count))
            .split(separator: "/").map(String.init)
        for component in components {
            current.appendPathComponent(component, isDirectory: true)
            if manager.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw RootFSRuntimeError.unsafePathComponent(component)
                }
            } else {
                try manager.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
        let resolved = target.resolvingSymlinksInPath().standardizedFileURL
        guard isSameOrDescendant(resolved, of: containerRoot.resolvingSymlinksInPath()) else {
            throw RootFSRuntimeError.pathEscapesApplicationSupport
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func isSameOrDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
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
    case invalidDirectory(String)
    case unsafeRootFS
    case unsafeLibraryPath(String)
    case unsafePathComponent(String)
    case pathEscapesApplicationSupport
    case noArm64Shell

    var errorDescription: String? {
        switch self {
        case .missingRootFS:
            return "RootFS runtime setup failed: import a Linux root filesystem first."
        case .invalidDirectory(let name):
            return "RootFS runtime setup failed: /\(name) is missing, unsafe or outside RootFS."
        case .unsafeRootFS:
            return "RootFS resolves outside its expected app container location."
        case .unsafeLibraryPath(let name):
            return "RootFS library path /\(name) resolves outside RootFS or is not a directory."
        case .unsafePathComponent(let name):
            return "Unsafe RootFS path component '\(name)': expected a real non-symlink directory."
        case .pathEscapesApplicationSupport:
            return "RootFS runtime path escapes the app's Application Support directory."
        case .noArm64Shell:
            return "RootFS runtime setup failed: no executable ARM64 Linux ELF shell was found."
        }
    }
}
