import Foundation

/// Фиксированные категории слайдера на Home.
///
/// Порт `ServerCategory.kt` (Android) и `ServerCategoryHelper.cs` (Windows):
/// сервер относится к вкладке по ТЕКСТУ своего имени из подписки, а не по
/// группе из админки. Поэтому все платформы делят одну и ту же подписку на
/// одинаковые вкладки с одинаковыми названиями.
public enum ServerCategory: String, Codable, CaseIterable, Sendable {
    case bypass
    case auto
    case speed
    case youtube
    case gaming

    /// Категории для чипов Home: «Авто» скрыта — авто-выбора сервера в
    /// приложении нет (как в эталонных Android/Windows-версиях).
    public static let homeFilters: [ServerCategory] = allCases.filter { $0 != .auto }

    /// Подходит ли имя сервера под эту категорию.
    public func matches(_ rawName: String) -> Bool {
        let name = rawName.lowercased()
        switch self {
        case .bypass:
            return Self.contains(Self.bypassMarkers, in: name)
        case .auto:
            // «Авто» — отдельная метка в имени, а не часть другого слова;
            // обходные серверы с «Авто» в названии остаются обходами.
            return Self.matchesAuto(name) && !Self.contains(Self.bypassMarkers, in: name)
        case .speed:
            return Self.contains(Self.speedMarkers, in: name)
        case .youtube:
            return Self.contains(Self.youtubeMarkers, in: name)
        case .gaming:
            return Self.contains(Self.gamingMarkers, in: name)
        }
    }

    /// Все категории, под которые попадает сервер.
    public static func categories(of server: Server) -> Set<ServerCategory> {
        Set(allCases.filter { $0.matches(server.rawName) })
    }

    // MARK: - Маркеры (совпадают с Android и Windows)

    private static let bypassMarkers = [
        "обход", "bypass", "белых ip", "белый ip", "white ip", "white-list", "whitelist"
    ]

    private static let speedMarkers = [
        "⚡", "ультра", "ultra", "скорость", "speed", "fast"
    ]

    private static let youtubeMarkers = [
        "youtube", "you tube", "ютуб", "youtu"
    ]

    private static let gamingMarkers = [
        "игровые", "игровой", "игра", "gaming", "game", "🎮"
    ]

    private static let autoRegex = try? NSRegularExpression(
        pattern: "(?:^|[^\\p{L}])авто(?:[^\\p{L}]|$)"
    )

    private static func contains(_ markers: [String], in name: String) -> Bool {
        markers.contains { name.contains($0) }
    }

    private static func matchesAuto(_ name: String) -> Bool {
        guard let regex = autoRegex else { return false }
        let range = NSRange(name.startIndex..., in: name)
        return regex.firstMatch(in: name, options: [], range: range) != nil
    }
}
