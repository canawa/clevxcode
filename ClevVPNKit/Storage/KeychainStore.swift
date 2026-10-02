import Foundation
import Security

/// Хранение ссылки подписки в Keychain — она даёт доступ к аккаунту,
/// поэтому в UserDefaults её класть нельзя.
public enum KeychainStore {
    private static let service = "com.clevvpn.ios"
    private static let subscriptionKey = "subscription-url"

    public static var subscriptionURL: String? {
        get { read(subscriptionKey) }
        set {
            if let value = newValue {
                write(subscriptionKey, value)
            } else {
                delete(subscriptionKey)
            }
        }
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        var query = baseQuery(key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
