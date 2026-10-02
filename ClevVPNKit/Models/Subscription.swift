import Foundation

/// Данные аккаунта из заголовка Subscription-Userinfo.
public struct SubscriptionUserInfo: Codable, Hashable, Sendable {
    public var uploadBytes: Int64?
    public var downloadBytes: Int64?
    public var totalBytes: Int64?
    public var expiresAt: Date?

    public var usedBytes: Int64? {
        guard uploadBytes != nil || downloadBytes != nil else { return nil }
        return (uploadBytes ?? 0) + (downloadBytes ?? 0)
    }

    /// Парсит "upload=123; download=456; total=789; expire=1710000000".
    public static func parse(_ header: String) -> SubscriptionUserInfo {
        var info = SubscriptionUserInfo()
        for pair in header.components(separatedBy: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let value = Int64(parts[1]) else { continue }
            switch parts[0].lowercased() {
            case "upload": info.uploadBytes = value
            case "download": info.downloadBytes = value
            case "total": info.totalBytes = value
            case "expire": info.expiresAt = value > 0 ? Date(timeIntervalSince1970: TimeInterval(value)) : nil
            default: break
            }
        }
        return info
    }
}

/// Результат загрузки подписки Remnawave.
public struct Subscription: Codable, Hashable, Sendable {
    public var servers: [Server]
    public var title: String?
    public var userInfo: SubscriptionUserInfo?
    public var announce: String?
    public var supportURL: String?
    public var updatedAt: Date
    /// Интервал автообновления подписки в часах (заголовок profile-update-interval).
    public var updateIntervalHours: Int?

    public init(servers: [Server],
                title: String? = nil,
                userInfo: SubscriptionUserInfo? = nil,
                announce: String? = nil,
                supportURL: String? = nil,
                updatedAt: Date = Date(),
                updateIntervalHours: Int? = nil) {
        self.servers = servers
        self.title = title
        self.userInfo = userInfo
        self.announce = announce
        self.supportURL = supportURL
        self.updatedAt = updatedAt
        self.updateIntervalHours = updateIntervalHours
    }

    /// Вкладки из админки в порядке появления серверов.
    public var adminGroups: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for server in servers {
            if let group = server.group, seen.insert(group).inserted {
                result.append(group)
            }
        }
        return result
    }
}

public enum SubscriptionError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case emptyOrUnparsable

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid subscription link", bundle: .clevVPNKit)
        case .httpError(let code):
            return String(format: String(localized: "Server returned error %d", bundle: .clevVPNKit), code)
        case .emptyOrUnparsable:
            return String(localized: "No servers found in subscription", bundle: .clevVPNKit)
        }
    }
}

extension Bundle {
    /// Бандл ClevVPNKit для локализованных строк фреймворка.
    public static var clevVPNKit: Bundle { Bundle(for: BundleToken.self) }
}

private final class BundleToken {}
