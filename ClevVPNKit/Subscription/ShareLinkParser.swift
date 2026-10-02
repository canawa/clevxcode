import Foundation

/// Парсер share-ссылок (vless:// trojan:// hysteria2:// ss://), которые отдаёт Remnawave.
public enum ShareLinkParser {

    /// Разбирает всё содержимое подписки: plain-текст со ссылками или base64 от него.
    public static func parseSubscriptionContent(_ content: String) -> [Server] {
        let text = decodeIfBase64(content)
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { parseLink($0) }
    }

    /// Одна ссылка → сервер. Неизвестные схемы и битые ссылки пропускаются.
    public static func parseLink(_ link: String) -> Server? {
        guard let scheme = link.components(separatedBy: "://").first?.lowercased() else { return nil }
        switch scheme {
        case "vless": return parseVLESS(link)
        case "trojan": return parseTrojan(link)
        case "hysteria2", "hy2": return parseHysteria2(link)
        case "ss": return parseShadowsocks(link)
        default: return nil
        }
    }

    // MARK: - VLESS

    private static func parseVLESS(_ link: String) -> Server? {
        guard let url = URLComponents(string: link),
              let uuid = url.user, !uuid.isEmpty,
              let host = url.host, let port = url.port else { return nil }
        let q = queryDict(url)

        let config = VLESSConfig(
            uuid: uuid,
            flow: q["flow"].flatMap { $0.isEmpty ? nil : $0 },
            tls: parseTLS(q, defaultSNI: host),
            transport: parseTransport(q)
        )
        return makeServer(remark: remark(url, fallback: host), host: host, port: port, kind: .vless(config))
    }

    // MARK: - Trojan

    private static func parseTrojan(_ link: String) -> Server? {
        guard let url = URLComponents(string: link),
              let password = url.user?.removingPercentEncoding, !password.isEmpty,
              let host = url.host, let port = url.port else { return nil }
        var q = queryDict(url)
        // У trojan security по умолчанию tls, даже если параметр не указан
        if q["security"] == nil { q["security"] = "tls" }

        let config = TrojanConfig(
            password: password,
            tls: parseTLS(q, defaultSNI: host),
            transport: parseTransport(q)
        )
        return makeServer(remark: remark(url, fallback: host), host: host, port: port, kind: .trojan(config))
    }

    // MARK: - Hysteria2

    private static func parseHysteria2(_ link: String) -> Server? {
        guard let url = URLComponents(string: link),
              let host = url.host, let port = url.port else { return nil }
        // auth может содержать ':' (user:pass) — берём весь userinfo
        var auth = url.user?.removingPercentEncoding ?? ""
        if let pass = url.password?.removingPercentEncoding, !pass.isEmpty {
            auth += ":\(pass)"
        }
        guard !auth.isEmpty else { return nil }
        let q = queryDict(url)

        var obfsPassword: String?
        if q["obfs"]?.lowercased() == "salamander" {
            obfsPassword = q["obfs-password"]
        }
        let config = Hysteria2Config(
            password: auth,
            serverName: q["sni"] ?? q["peer"],
            allowInsecure: boolValue(q["insecure"]) || boolValue(q["allowinsecure"]),
            obfsPassword: obfsPassword,
            portRange: (q["mport"] ?? q["ports"]).map { $0.replacingOccurrences(of: "-", with: ":") }
        )
        return makeServer(remark: remark(url, fallback: host), host: host, port: port, kind: .hysteria2(config))
    }

    // MARK: - Shadowsocks (SIP002)

    private static func parseShadowsocks(_ link: String) -> Server? {
        guard let url = URLComponents(string: link),
              let host = url.host, let port = url.port,
              let userinfo = url.user else { return nil }

        var method: String?
        var password: String?
        if let decoded = base64Decode(userinfo), decoded.contains(":") {
            // SIP002: base64url("method:password")
            let parts = decoded.split(separator: ":", maxSplits: 1).map(String.init)
            method = parts.first
            password = parts.count > 1 ? parts[1] : nil
        } else if let plainPassword = url.password {
            // Незакодированный вариант method:password
            method = userinfo.removingPercentEncoding
            password = plainPassword.removingPercentEncoding
        }
        guard let m = method, let p = password, !m.isEmpty else { return nil }

        let config = ShadowsocksConfig(method: m, password: p)
        return makeServer(remark: remark(url, fallback: host), host: host, port: port, kind: .shadowsocks(config))
    }

    // MARK: - Общие куски

    private static func parseTLS(_ q: [String: String], defaultSNI: String) -> TLSConfig {
        let security: TLSConfig.Security
        switch q["security"]?.lowercased() {
        case "reality": security = .reality
        case "tls", "xtls": security = .tls
        default: security = .none
        }
        let alpn = q["alpn"]?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []

        return TLSConfig(
            security: security,
            serverName: q["sni"] ?? q["peer"] ?? (security == .none ? nil : defaultSNI),
            alpn: alpn,
            fingerprint: q["fp"].flatMap { $0.isEmpty ? nil : $0 },
            allowInsecure: boolValue(q["allowinsecure"]) || boolValue(q["insecure"]),
            realityPublicKey: q["pbk"],
            realityShortID: q["sid"]
        )
    }

    private static func parseTransport(_ q: [String: String]) -> TransportConfig {
        let type: TransportType
        switch q["type"]?.lowercased() {
        case "ws", "websocket": type = .ws
        case "grpc", "gun": type = .grpc
        case "httpupgrade": type = .httpupgrade
        default: type = .tcp
        }
        return TransportConfig(
            type: type,
            path: q["path"],
            host: q["host"],
            serviceName: q["servicename"]
        )
    }

    private static func makeServer(remark: String, host: String, port: Int, kind: ServerKind) -> Server {
        let (group, name) = splitGroup(remark)
        return Server(
            name: stripFlagEmoji(name),
            rawName: remark,
            group: group,
            countryCode: detectCountry(remark),
            host: host,
            port: port,
            kind: kind
        )
    }

    /// Вкладки из админки: "Группа | Имя сервера" в названии хоста Remnawave.
    static func splitGroup(_ remark: String) -> (group: String?, name: String) {
        let parts = remark.components(separatedBy: "|")
        guard parts.count >= 2 else { return (nil, remark.trimmingCharacters(in: .whitespaces)) }
        let group = parts[0].trimmingCharacters(in: .whitespaces)
        let name = parts.dropFirst().joined(separator: "|").trimmingCharacters(in: .whitespaces)
        guard !group.isEmpty, !name.isEmpty else { return (nil, remark.trimmingCharacters(in: .whitespaces)) }
        return (group, name)
    }

    /// Тематическая вкладка сервера по ключевым словам в названии
    /// (Авто, Обходы, Ютуб, Игровые, Скорость). nil — попадёт только во «Все».
    public static func detectCategory(_ remark: String) -> String? {
        let lower = remark.lowercased()
        for (keywords, label) in categories {
            if keywords.contains(where: { lower.contains($0) }) {
                return label
            }
        }
        return nil
    }

    private static let categories: [(keywords: [String], label: String)] = [
        (["авто", "auto"], "Авто"),
        (["обход", "глушил", "моб. интернет", "моб.интернет", "моб инет", "моб. инет"], "Обходы"),
        (["youtube", "ютуб", "instagram", "инстаграм", "медиа"], "Ютуб"),
        (["игр", "gaming", "game", "гейм"], "Игровые"),
        (["ультра", "скорост", "speed", "premium", "премиум", "turbo"], "Скорость")
    ]

    /// Убирает флаг-эмодзи из отображаемого имени — флаг рисуется отдельно в UI.
    static func stripFlagEmoji(_ name: String) -> String {
        let stripped = String(name.unicodeScalars.filter { !(0x1F1E6...0x1F1FF).contains($0.value) })
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? name : stripped
    }

    /// Страна: флаг-эмодзи в имени, иначе ISO-код или название страны текстом.
    static func detectCountry(_ remark: String) -> String? {
        // 1. Флаг-эмодзи (пара regional indicator symbols)
        var indicators: [UInt32] = []
        for scalar in remark.unicodeScalars {
            if (0x1F1E6...0x1F1FF).contains(scalar.value) {
                indicators.append(scalar.value - 0x1F1E6 + UInt32(UnicodeScalar("A").value))
                if indicators.count == 2 {
                    return String(indicators.compactMap { UnicodeScalar($0).map(Character.init) })
                }
            } else {
                indicators.removeAll()
            }
        }
        // 2. Название страны или ISO-код словом
        let lower = remark.lowercased()
        for (needle, code) in Self.countryNames {
            if lower.contains(needle) { return code }
        }
        return nil
    }

    private static let countryNames: [(String, String)] = [
        ("германи", "DE"), ("germany", "DE"), ("frankfurt", "DE"), ("франкфурт", "DE"),
        ("нидерланд", "NL"), ("netherlands", "NL"), ("amsterdam", "NL"), ("амстердам", "NL"),
        ("финлянд", "FI"), ("finland", "FI"), ("хельсинки", "FI"), ("helsinki", "FI"),
        ("франци", "FR"), ("france", "FR"), ("париж", "FR"), ("paris", "FR"),
        ("сша", "US"), ("usa", "US"), ("united states", "US"), ("америка", "US"),
        ("великобритан", "GB"), ("англи", "GB"), ("london", "GB"), ("лондон", "GB"), (" uk ", "GB"),
        ("турци", "TR"), ("turkey", "TR"), ("стамбул", "TR"), ("istanbul", "TR"),
        ("росси", "RU"), ("russia", "RU"), ("москва", "RU"), ("moscow", "RU"),
        ("казахстан", "KZ"), ("kazakhstan", "KZ"),
        ("япони", "JP"), ("japan", "JP"), ("токио", "JP"), ("tokyo", "JP"),
        ("сингапур", "SG"), ("singapore", "SG"),
        ("швеци", "SE"), ("sweden", "SE"), ("стокгольм", "SE"),
        ("польш", "PL"), ("poland", "PL"), ("варшав", "PL"),
        ("латви", "LV"), ("latvia", "LV"), ("рига", "LV"),
        ("испани", "ES"), ("spain", "ES"), ("мадрид", "ES"),
        ("итали", "IT"), ("italy", "IT"), ("милан", "IT"),
        ("австри", "AT"), ("austria", "AT"), ("вена", "AT"),
        ("швейцари", "CH"), ("switzerland", "CH"), ("цюрих", "CH"),
        ("канад", "CA"), ("canada", "CA"),
        ("гонконг", "HK"), ("hong kong", "HK"), ("hongkong", "HK"),
        ("оаэ", "AE"), ("дубай", "AE"), ("dubai", "AE"), ("uae", "AE"),
        ("израил", "IL"), ("israel", "IL"),
        ("чехи", "CZ"), ("czech", "CZ"), ("прага", "CZ"),
        ("эстони", "EE"), ("estonia", "EE"), ("таллин", "EE"),
        ("литв", "LT"), ("lithuania", "LT"), ("вильнюс", "LT"),
        ("украин", "UA"), ("ukraine", "UA"), ("киев", "UA"),
        ("молдов", "MD"), ("moldova", "MD"), ("кишинев", "MD"), ("кишинёв", "MD"),
        ("армени", "AM"), ("armenia", "AM"), ("ереван", "AM"),
        ("грузи", "GE"), ("georgia", "GE"), ("тбилиси", "GE"),
        ("серби", "RS"), ("serbia", "RS"), ("белград", "RS"),
        ("румыни", "RO"), ("romania", "RO"), ("бухарест", "RO"),
        ("болгари", "BG"), ("bulgaria", "BG"), ("софия", "BG"),
        ("венгри", "HU"), ("hungary", "HU"), ("будапешт", "HU"),
        ("норвеги", "NO"), ("norway", "NO"), ("осло", "NO"),
        ("дани", "DK"), ("denmark", "DK"), ("копенгаген", "DK"),
        ("бельги", "BE"), ("belgium", "BE"), ("брюссель", "BE"),
        ("португали", "PT"), ("portugal", "PT"), ("лиссабон", "PT"),
        ("греци", "GR"), ("greece", "GR"), ("афины", "GR"),
        ("инди", "IN"), ("india", "IN"),
        ("корея", "KR"), ("korea", "KR"), ("сеул", "KR"),
        ("бразили", "BR"), ("brazil", "BR"),
        ("австрали", "AU"), ("australia", "AU"), ("сидней", "AU")
    ]

    // MARK: - Утилиты

    private static func remark(_ url: URLComponents, fallback: String) -> String {
        guard let fragment = url.fragment?.removingPercentEncoding?.trimmingCharacters(in: .whitespaces),
              !fragment.isEmpty else { return fallback }
        return fragment
    }

    private static func queryDict(_ url: URLComponents) -> [String: String] {
        var dict: [String: String] = [:]
        for item in url.queryItems ?? [] {
            dict[item.name.lowercased()] = item.value?.removingPercentEncoding ?? item.value
        }
        return dict
    }

    private static func boolValue(_ value: String?) -> Bool {
        guard let v = value?.lowercased() else { return false }
        return v == "1" || v == "true" || v == "yes"
    }

    /// Пробует декодировать base64/base64url; если не выходит — возвращает исходный текст.
    static func decodeIfBase64(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") { return trimmed }
        if let decoded = base64Decode(trimmed), decoded.contains("://") { return decoded }
        return trimmed
    }

    static func base64Decode(_ input: String) -> String? {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
