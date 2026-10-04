import Foundation

/// Режим маршрутизации трафика.
public enum RoutingMode: String, Codable, CaseIterable, Sendable {
    /// Весь трафик через VPN.
    case global
    /// Умный режим: российские сайты и локальные сети — напрямую, остальное через VPN.
    case smart
    /// Только пользовательские правила поверх глобального режима.
    case custom
}

/// Пользовательское правило маршрутизации (домен или IP/CIDR).
public struct RoutingRule: Codable, Identifiable, Hashable, Sendable {
    public enum Target: String, Codable, Sendable {
        /// Мимо VPN, напрямую.
        case direct
        /// Через VPN.
        case proxy
    }

    public enum Matcher: String, Codable, Sendable {
        case domainSuffix
        case ipCIDR
    }

    public var id: UUID
    public var value: String
    public var matcher: Matcher
    public var target: Target
    public var isEnabled: Bool

    public init(value: String, matcher: Matcher, target: Target, isEnabled: Bool = true) {
        self.id = UUID()
        self.value = value
        self.matcher = matcher
        self.target = target
        self.isEnabled = isEnabled
    }
}

/// Пользовательская папка серверов (клиентские «вкладки»).
public struct ServerFolder: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var serverIDs: [String]

    public init(name: String, serverIDs: [String] = []) {
        self.id = UUID()
        self.name = name
        self.serverIDs = serverIDs
    }
}
