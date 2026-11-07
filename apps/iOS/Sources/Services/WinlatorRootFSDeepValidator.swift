import Foundation

struct WinlatorRootFSDeepReport {
    let checks: [String]
    let isReady: Bool
    var message: String {
        (["ARM64 RootFS deep validation", ""] + checks +
         ["", "Structural validation only; it does not execute Linux binaries."]).joined(separator: "\n")
    }
}

enum WinlatorRootFSDeepValidator {
    static func inspect(for container: WinlatorContainer) -> WinlatorRootFSDeepReport {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
            let root = support.appendingPathComponent(
                "Winlator/Containers/\(container.id.uuidString)/rootfs", isDirectory: true
            ).standardizedFileURL
            let manager = FileManager.default
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return WinlatorRootFSDeepReport(checks: ["✗ RootFS has not been imported."], isReady: false)
            }

            let shellPaths = ["bin/sh", "usr/bin/sh", "bin/bash", "usr/bin/bash"]
            guard let shell = shellPaths.map({ root.appendingPathComponent($0) })
                .first(where: { manager.isExecutableFile(atPath: $0.path) && elfMachine($0) == 183 }) else {
                return WinlatorRootFSDeepReport(checks: ["✗ No executable AArch64 Linux shell found."], isReady: false)
            }

            var checks = ["✓ Executable AArch64 shell: /\(shellPaths.first { root.appendingPathComponent($0) == shell } ?? "bin/sh")"]
            guard let interpreterInfo = interpreterInfo(in: shell) else {
                return WinlatorRootFSDeepReport(
                    checks: checks + ["✗ ELF program-header table is malformed or unreadable."],
                    isReady: false
                )
            }
            guard interpreterInfo.present else {
                checks.append("✓ No PT_INTERP entry; shell is statically linked.")
                return WinlatorRootFSDeepReport(checks: checks, isReady: true)
            }
            guard let interpreter = interpreterInfo.path, !interpreter.isEmpty else {
                checks.append("✗ PT_INTERP entry exists but its path is malformed.")
                return WinlatorRootFSDeepReport(checks: checks, isReady: false)
            }

            checks.append("✓ ELF PT_INTERP: \(interpreter)")
            let relative = interpreter.hasPrefix("/") ? String(interpreter.dropFirst()) : interpreter
            let linker = root.appendingPathComponent(relative).standardizedFileURL
            guard linker.path.hasPrefix(root.path + "/"), manager.isExecutableFile(atPath: linker.path),
                  elfMachine(linker) == 183 else {
                checks.append("✗ Dynamic linker missing, non-executable or not AArch64: \(interpreter)")
                return WinlatorRootFSDeepReport(checks: checks, isReady: false)
            }
            checks.append("✓ AArch64 dynamic linker exists and has executable permission")

            let libraryRoots = ["lib", "lib64", "usr/lib", "usr/lib/aarch64-linux-gnu",
                                "lib/aarch64-linux-gnu", "usr/local/lib"]
                .map { root.appendingPathComponent($0, isDirectory: true) }
                .filter { manager.fileExists(atPath: $0.path) }
            let hasLibc = libraryRoots.contains { directory in
                ["libc.so.6", "libc.musl-aarch64.so.1"].contains {
                    manager.fileExists(atPath: directory.appendingPathComponent($0).path)
                }
            }
            checks.append("\(hasLibc ? "✓" : "✗") C runtime library (glibc or musl)")
            let hasLibgcc = libraryRoots.contains {
                manager.fileExists(atPath: $0.appendingPathComponent("libgcc_s.so.1").path)
            }
            checks.append("\(hasLibgcc ? "✓" : "•") libgcc_s.so.1 (optional on some distributions)")
            return WinlatorRootFSDeepReport(checks: checks, isReady: hasLibc)
        } catch {
            return WinlatorRootFSDeepReport(checks: ["✗ Validation error: \(error.localizedDescription)"], isReady: false)
        }
    }

    private static func elfMachine(_ url: URL) -> UInt16? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 20), header.count >= 20 else { return nil }
        let b = [UInt8](header)
        guard b[0...3].elementsEqual([0x7F, 0x45, 0x4C, 0x46]), b[4] == 2, b[5] == 1 else { return nil }
        return UInt16(b[18]) | (UInt16(b[19]) << 8)
    }

    private static func interpreterInfo(in url: URL) -> (present: Bool, path: String?)? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), data.count >= 64 else { return nil }
        let b = [UInt8](data.prefix(64))
        guard b[0...3].elementsEqual([0x7F, 0x45, 0x4C, 0x46]), b[4] == 2, b[5] == 1 else { return nil }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | (UInt16(b[i + 1]) << 8) }
        func u64(_ i: Int) -> UInt64 {
            (0..<8).reduce(UInt64(0)) { $0 | (UInt64(b[i + $1]) << (8 * $1)) }
        }
        let phoff = u64(32)
        let phentsize = UInt64(u16(54))
        let phnum = UInt64(u16(56))
        guard phentsize >= 56, phnum <= 4096, phoff <= UInt64(data.count),
              phoff + phentsize * phnum <= UInt64(data.count) else { return nil }
        for index in 0..<phnum {
            let offset = Int(phoff + index * phentsize)
            let p = [UInt8](data[offset..<offset + 56])
            let type = UInt32(p[0]) | (UInt32(p[1]) << 8) | (UInt32(p[2]) << 16) | (UInt32(p[3]) << 24)
            guard type == 3 else { continue } // PT_INTERP
            let fileOffset = (0..<8).reduce(UInt64(0)) { $0 | (UInt64(p[8 + $1]) << (8 * $1)) }
            let fileSize = (0..<8).reduce(UInt64(0)) { $0 | (UInt64(p[32 + $1]) << (8 * $1)) }
            guard fileSize > 1, fileSize <= 4096, fileOffset + fileSize <= UInt64(data.count) else {
                return (true, nil)
            }
            let bytes = data[Int(fileOffset)..<Int(fileOffset + fileSize)]
            return (true, String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8))
        }
        return (false, nil)
    }
}
