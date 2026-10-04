import Foundation

/// Общее хранилище приложения и туннельного расширения (App Group).
public enum SharedStore {
    public static let appGroupID = "group.com.clevvpn.ios"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Контейнер App Group. В юнит-тестах/без entitlement — временная папка.
    public static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("clevvpn-dev", isDirectory: true)
    }

    /// Рабочая папка sing-box (конфиг, кэш, rule-set'ы).
    public static var workingDirectory: URL {
        let url = containerURL.appendingPathComponent("sing-box", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var configURL: URL {
        workingDirectory.appendingPathComponent("config.json")
    }

    // MARK: - Настройки

    private enum Key {
        static let selectedServerID = "selectedServerID"
        static let routingMode = "routingMode"
        static let killSwitch = "killSwitchEnabled"
        static let statusFlag = "statusFlagEnabled"
        static let customRules = "customRules"
        static let folders = "serverFolders"
        static let favorites = "favoriteServerIDs"
        static let recent = "recentServerIDs"
        static let tabOrder = "tabOrder"
        static let cachedSubscription = "cachedSubscription"
        static let pingResults = "pingResults"
        static let excludeLAN = "excludeLAN"
    }

    public static var selectedServerID: String? {
        get { defaults.string(forKey: Key.selectedServerID) }
        set { defaults.set(newValue, forKey: Key.selectedServerID) }
    }

    public static var routingMode: RoutingMode {
        get { defaults.string(forKey: Key.routingMode).flatMap(RoutingMode.init) ?? .smart }
        set { defaults.set(newValue.rawValue, forKey: Key.routingMode) }
    }

    /// Kill Switch: при обрыве VPN блокировать интернет (защита от утечки IP).
    public static var killSwitchEnabled: Bool {
        get { defaults.bool(forKey: Key.killSwitch) }
        set { defaults.set(newValue, forKey: Key.killSwitch) }
    }

    /// Показывать флаг подключённой страны в меню-баре / Dynamic Island.
    public static var statusFlagEnabled: Bool {
        get { defaults.object(forKey: Key.statusFlag) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.statusFlag) }
    }

    public static var customRules: [RoutingRule] {
        get { decode([RoutingRule].self, forKey: Key.customRules) ?? [] }
        set { encode(newValue, forKey: Key.customRules) }
    }

    public static var folders: [ServerFolder] {
        get { decode([ServerFolder].self, forKey: Key.folders) ?? [] }
        set { encode(newValue, forKey: Key.folders) }
    }

    public static var favoriteServerIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.favorites) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.favorites) }
    }

    /// Последние использованные серверы (свежие первыми) — для меню-бара.
    public static var recentServerIDs: [String] {
        get { defaults.stringArray(forKey: Key.recent) ?? [] }
        set { defaults.set(newValue, forKey: Key.recent) }
    }

    /// Пользовательский порядок вкладок-групп (перетаскиванием).
    public static var tabOrder: [String] {
        get { defaults.stringArray(forKey: Key.tabOrder) ?? [] }
        set { defaults.set(newValue, forKey: Key.tabOrder) }
    }

    /// Группы в пользовательском порядке: известные — по сохранённому порядку,
    /// новые (из свежей подписки) — в конец.
    public static func ordered(groups: [String]) -> [String] {
        var result = tabOrder.filter { groups.contains($0) }
        for g in groups where !result.contains(g) { result.append(g) }
        return result
    }

    /// Кэш последней подписки — приложение работает и без сети.
    public static var cachedSubscription: Subscription? {
        get { decode(Subscription.self, forKey: Key.cachedSubscription) }
        set { encode(newValue, forKey: Key.cachedSubscription) }
    }

    /// Последние результаты пинга: server.id → миллисекунды (-1 = недоступен).
    public static var pingResults: [String: Int] {
        get { decode([String: Int].self, forKey: Key.pingResults) ?? [:] }
        set { encode(newValue, forKey: Key.pingResults) }
    }

    // MARK: - Codable helpers

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
