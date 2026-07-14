import Foundation
import Security

/// Minimal Keychain wrapper for small secrets (the passcode hash + salt, the
/// opt-in Anthropic API key). Items are stored `WhenUnlockedThisDeviceOnly`
/// so they never sync or leave the device.
enum KeychainStore {
    private static let service = "com.ogureq.gemocode.lock"

    @discardableResult
    static func set(_ data: Data, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: String convenience

    @discardableResult
    static func set(_ string: String, for account: String) -> Bool {
        set(Data(string.utf8), for: account)
    }

    static func getString(_ account: String) -> String? {
        guard let data = get(account) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
