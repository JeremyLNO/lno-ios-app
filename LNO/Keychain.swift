import Foundation
import Security

/// Minimal Keychain wrapper for the JWT. Tokens are sensitive; UserDefaults would
/// leak them in backups.
enum Keychain {
    private static let account = "lno_jwt"
    private static let service = "company.lno.controlcenter"
    /// Who signed in with Google last, so the sign-in screen can offer that account
    /// again instead of a bare "Sign in with Google". Name/email/photo of the device
    /// owner — not a credential, but kept here rather than UserDefaults so it never
    /// rides along in an unencrypted backup.
    static let lastGoogleUserAccount = "lno_last_google_user"

    static func save(_ token: String, account: String = Keychain.account) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(account: String = Keychain.account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func clear(account: String = Keychain.account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
