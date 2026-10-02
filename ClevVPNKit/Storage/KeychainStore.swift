import Foundation
#if os(iOS)
import Security
#endif

/// Хранение ссылки подписки.
///
/// iOS — Keychain (ссылка = доступ к аккаунту).
/// macOS — файл в Application Support: Debug-сборки с ad-hoc подписью
/// каждый раз «чужие» для Keychain, из‑за этого macOS вечно показывает
/// диалог пароля связки ключей. Файл этого окна не вызывает.
public enum KeychainStore {
    private static let subscriptionKey = "subscription-url"

    public static var subscriptionURL: String? {
        get {
            #if os(macOS)
            return readFile()
            #else
            return readKeychain(subscriptionKey)
            #endif
        }
        set {
            #if os(macOS)
            if let value = newValue {
                writeFile(value)
            } else {
                deleteFile()
            }
            #else
            if let value = newValue {
                writeKeychain(subscriptionKey, value)
            } else {
                deleteKeychain(subscriptionKey)
            }
            #endif
        }
    }

    // MARK: - macOS (файл)

    #if os(macOS)
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClevVPN", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("subscription-url.txt")
    }

    private static func readFile() -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func writeFile(_ value: String) {
        try? value.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func deleteFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
    #endif

    // MARK: - iOS (Keychain)

    #if os(iOS)
    private static let service = "com.clevvpn.ios"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func readKeychain(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        var query = baseQuery(key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func deleteKeychain(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
    #endif
}
