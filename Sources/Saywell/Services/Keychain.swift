import Foundation
import Security

/// Provider credentials in the macOS Keychain, one item per provider account.
/// Credentials are never written to settings, logs, exports or prompts.
enum Keychain {
    static let service = "app.saywell.credentials"
    /// Service name used by Govori 0.2. Read only on an explicit user action.
    static let legacyService = "local.govori.voice.openai"

    private static func query(_ account: String, service: String = service) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? { read(query(account)) }

    private static func read(_ base: [String: Any]) -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Checks presence without returning the secret.
    static func exists(_ account: String) -> Bool {
        var q = query(account)
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    enum SaveError: Error { case empty, keychain(OSStatus) }

    static func save(_ value: String, account: String) throws {
        let secret = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty, !secret.contains(where: \.isWhitespace) else { throw SaveError.empty }
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let add = SecItemAdd(q as CFDictionary, nil)
            guard add == errSecSuccess else { throw SaveError.keychain(add) }
        } else if status != errSecSuccess {
            throw SaveError.keychain(status)
        }
    }

    static func remove(_ account: String) { SecItemDelete(query(account) as CFDictionary) }

    /// Copies the OpenAI key saved by Govori 0.2. macOS asks the person to allow access because
    /// the item belongs to the old app. The old item is left untouched.
    static func importLegacyOpenAIKey() -> Bool {
        guard let key = read(query("api-key", service: legacyService)), !key.isEmpty else { return false }
        return (try? save(key, account: "openai")) != nil
    }
}
