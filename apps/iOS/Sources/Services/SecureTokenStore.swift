import Foundation
import Security

enum SecureTokenStoreError: LocalizedError {
    case keychainFailure(OSStatus)
    case invalidStoredValue

    var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            return "Secure token storage failed (Keychain status \(status))."
        case .invalidStoredValue:
            return "The saved backend token could not be read."
        }
    }
}

enum SecureTokenStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.winlator.ios"
    private static let account = "control-plane-bearer-token"

    static func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecureTokenStoreError.keychainFailure(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw SecureTokenStoreError.invalidStoredValue
        }
        return token
    }

    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecureTokenStoreError.keychainFailure(addStatus)
            }
        } else if status != errSecSuccess {
            throw SecureTokenStoreError.keychainFailure(status)
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureTokenStoreError.keychainFailure(status)
        }
    }
}
