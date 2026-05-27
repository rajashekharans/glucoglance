import Foundation
import Security

/// A thin wrapper around the iOS Keychain for storing credentials and the
/// LibreLinkUp bearer token.
///
/// Items are stored as `kSecClassGenericPassword` with accessibility
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — they're readable after
/// the user unlocks the device once after boot, and never sync to iCloud.
///
/// Sharing between the iOS app and the watch app happens via the
/// `keychain-access-groups` entitlement (`$(AppIdentifierPrefix)com.rajnaidu.LibreGlucoseWatch.shared`).
/// Both targets declare the same single group, so queries that omit
/// `kSecAttrAccessGroup` default to it — no team-ID prefix needs to be
/// hard-coded in Swift.
public final class KeychainStore {

    public static let shared = KeychainStore()
    private init() {}

    // MARK: - Public API

    @discardableResult
    public func setString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return setData(data, forKey: key)
    }

    public func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func setData(_ value: Data, forKey key: String) -> Bool {
        // Always delete first so we get an idempotent "set". Avoids
        // errSecDuplicateItem and lets us update existing items.
        _ = delete(forKey: key)

        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: value,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func getData(forKey key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    public func delete(forKey key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Wipes every item this app has stored in Keychain. Used by clearSession().
    public func deleteAll() {
        for key in [Keys.password, Keys.token, Keys.userId] {
            delete(forKey: key)
        }
    }

    // MARK: - Well-known keys

    public enum Keys {
        public static let password = "llu_password"
        public static let token    = "llu_token"
        public static let userId   = "llu_user_id"
    }
}
