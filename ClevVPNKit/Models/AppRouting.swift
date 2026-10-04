import Foundation

/// Режим маршрутизации по приложениям (только macOS — iOS не даёт
/// определить процесс-владелец соединения).
public enum AppRoutingMode: String, Codable, CaseIterable, Sendable {
    /// Правила приложений выключены.
    case off
    /// Выбранные приложения идут мимо VPN, остальное — по обычным правилам.
    case bypassSelected
    /// Через VPN идут только выбранные приложения, всё остальное — напрямую.
    case onlySelected
}

/// Правило для одного приложения.
public struct AppRule: Codable, Identifiable, Hashable, Sendable {
    public var id: String { bundlePath }
    /// Отображаемое имя ("Telegram").
    public var name: String
    /// Путь к .app-бандлу ("/Applications/Telegram.app").
    public var bundlePath: String

    public init(name: String, bundlePath: String) {
        self.name = name
        self.bundlePath = bundlePath
    }

    /// Regex для sing-box process_path_regex: ловит и сам процесс, и все
    /// helper-процессы внутри бандла (например, Chrome Helper).
    ///
    /// ВАЖНО: sing-box использует Go-regexp (RE2), где слэш `/` НЕ экранируется.
    /// NSRegularExpression.escapedPattern (ICU) экранирует его в `\/`, что для RE2
    /// невалидно — правило молча не срабатывает. Поэтому экранируем вручную только
    /// настоящие метасимволы RE2, слэши оставляем как есть.
    public var processPathRegex: String {
        let metachars = Set(".^$*+?()[]{}|\\")
        let escaped = bundlePath.map { ch in
            metachars.contains(ch) ? "\\\(ch)" : String(ch)
        }.joined()
        return "^" + escaped + "/"
    }
}

extension SharedStore {
    private enum AppKey {
        static let appRules = "appRules"
        static let appRoutingMode = "appRoutingMode"
    }

    public static var appRules: [AppRule] {
        get {
            guard let data = defaults.data(forKey: AppKey.appRules) else { return [] }
            return (try? JSONDecoder().decode([AppRule].self, from: data)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: AppKey.appRules)
        }
    }

    public static var appRoutingMode: AppRoutingMode {
        get { defaults.string(forKey: AppKey.appRoutingMode).flatMap(AppRoutingMode.init) ?? .off }
        set { defaults.set(newValue.rawValue, forKey: AppKey.appRoutingMode) }
    }
}
