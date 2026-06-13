import Foundation
import Security

/// Thin wrapper around Keychain Services. Used by AppLockManager to store the
/// user's PIN. Ported verbatim from Spendy, with service updated to `nc.Anka`.
struct KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    private let service = "nc.Anka"

    /// Stores `value` under `key`. Returns `true` only when the keychain write
    /// actually succeeded — callers (e.g. `AppLockManager.savePIN`) must not
    /// flip `hasPIN`/`appLockEnabled` on a silent failure, or the user enables
    /// App Lock with no stored credential and gets locked out forever (S3).
    ///
    /// The item is written with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
    /// so the PIN credential is reachable only while the device is unlocked and
    /// **never** migrates to another device via an encrypted backup (S2).
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        return status == errSecSuccess
    }

    func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the item for `key`. Returns `true` when the item was deleted or
    /// was already absent — both are a successful end state.
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
