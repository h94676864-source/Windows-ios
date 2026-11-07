import Foundation
import CryptoKit

struct WinlatorInstallerInspection {
    let format: String
    let architecture: String
    let byteCount: Int64
    let sha256: String
    let isStructurallyValid: Bool
    let details: [String]

    var summary: String {
        ([
            "Format: \(format)",
            "Architecture: \(architecture)",
            "Size: \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))",
            "SHA-256: \(sha256)",
            "Structure: \(isStructurallyValid ? "Valid" : "Invalid")",
        ] + details).joined(separator: "\n")
    }
}

enum WinlatorInstallerInspector {
    static func inspect(_ url: URL) throws -> WinlatorInstallerInspection {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let rawSize = values.fileSize, rawSize > 0 else {
            throw InspectionError.invalidFile
        }

        let hash = try sha256(of: url)
        let ext = url.pathExtension.lowercased()
        let size = Int64(rawSize)

        switch ext {
        case "exe":
            let result = try inspectPE(url)
            return WinlatorInstallerInspection(
                format: "Windows PE executable",
                architecture: result.architecture,
                byteCount: size,
                sha256: hash,
                isStructurallyValid: result.valid,
                details: result.details
            )
        case "msi":
            let header = try readPrefix(url, count: 8)
            let expected: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
            let valid = Array(header) == expected
            return WinlatorInstallerInspection(
                format: "Windows Installer (MSI)",
                architecture: valid ? "Package metadata required" : "Unknown",
                byteCount: size,
                sha256: hash,
                isStructurallyValid: valid,
                details: [valid
                    ? "Compound File Binary container signature detected."
                    : "MSI compound-file signature is missing."]
            )
        default:
            throw InspectionError.unsupportedType
        }
    }

    private static func inspectPE(_ url: URL) throws -> (architecture: String, valid: Bool, details: [String]) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let dos = try handle.read(upToCount: 64) ?? Data()
        guard dos.count >= 64, dos[0] == 0x4D, dos[1] == 0x5A else {
            return ("Unknown", false, ["DOS MZ header is missing or truncated."])
        }
        let peOffset = UInt64(readUInt32(dos, at: 0x3C))
        guard peOffset <= UInt64(Int.max), peOffset >= 64 else {
            return ("Unknown", false, ["PE header offset is invalid."])
        }
        try handle.seek(toOffset: peOffset)
        let header = try handle.read(upToCount: 256) ?? Data()
        guard header.count >= 26,
              header[0] == 0x50, header[1] == 0x45, header[2] == 0, header[3] == 0 else {
            return ("Unknown", false, ["PE signature or COFF header is missing."])
        }

        let machine = readUInt16(header, at: 4)
        let architecture: String
        switch machine {
        case 0x014C: architecture = "x86 (32-bit)"
        case 0x8664: architecture = "x64 (AMD64)"
        case 0xAA64: architecture = "ARM64"
        case 0x01C0, 0x01C4: architecture = "ARM (32-bit)"
        default: architecture = String(format: "Unknown machine (0x%04X)", machine)
        }
        let optionalMagic = readUInt16(header, at: 24)
        guard optionalMagic == 0x10B || optionalMagic == 0x20B else {
            return (architecture, false, ["Optional-header signature is invalid."])
        }
        let subsystem = header.count >= 94 ? readUInt16(header, at: 24 + 68) : 0
        let subsystemName: String
        switch subsystem {
        case 2: subsystemName = "Windows GUI"
        case 3: subsystemName = "Windows console"
        case 1: subsystemName = "Native"
        default: subsystemName = subsystem == 0 ? "Unavailable" : "Subsystem \(subsystem)"
        }
        return (architecture, true, [
            "PE signature and optional header are structurally valid.",
            "Subsystem: \(subsystemName).",
            "This identifies the binary format; it does not prove Wine compatibility."
        ])
    }

    private static func readPrefix(_ url: URL, count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: count) ?? Data()
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }

    private enum InspectionError: LocalizedError {
        case invalidFile
        case unsupportedType
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Installer is empty or is not a regular file."
            case .unsupportedType: return "Only EXE and MSI installers can be inspected."
            }
        }
    }
}
