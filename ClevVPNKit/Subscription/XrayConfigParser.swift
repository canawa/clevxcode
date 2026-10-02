import Foundation

/// Парсер Xray-JSON подписки (формат, который Remnawave отдаёт клиенту Happ):
/// массив объектов `{ remarks, outbounds: [...], ... }` — по одному «профилю» на сервер.
/// Извлекает из outbound с тегом proxy наши модели Server.
public enum XrayConfigParser {

    /// true, если тело подписки — Xray-JSON (а не share-ссылки или sing-box-JSON).
    public static func looksLikeXrayJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return false }
        // Xray-профиль содержит "outbounds"; sing-box-подписка так не выглядит (объект, не массив)
        return trimmed.contains("\"outbounds\"")
    }

    public static func parse(_ content: String) -> [Server] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let profiles = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return profiles.compactMap { parseProfile($0) }
    }

    private static func parseProfile(_ profile: [String: Any]) -> Server? {
        let remark = (profile["remarks"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        // Server Description из Remnawave (Xray/Happ): meta.serverDescription
        let description = (profile["meta"] as? [String: Any])?["serverDescription"] as? String
        let cleanDescription = description?.trimmingCharacters(in: .whitespaces)
        guard let outbounds = profile["outbounds"] as? [[String: Any]] else { return nil }
        // Рабочий outbound — обычно tag == proxy; иначе первый транспортный протокол
        let proxy = outbounds.first { ($0["tag"] as? String) == "proxy" }
            ?? outbounds.first { ["vless", "trojan", "shadowsocks", "hysteria", "hysteria2"].contains($0["protocol"] as? String ?? "") }
        guard let outbound = proxy else { return nil }
        return parseOutbound(outbound, remark: remark,
                             description: (cleanDescription?.isEmpty ?? true) ? nil : cleanDescription)
    }

    static func parseOutbound(_ outbound: [String: Any], remark: String, description: String? = nil) -> Server? {
        guard let proto = outbound["protocol"] as? String else { return nil }
        let settings = outbound["settings"] as? [String: Any] ?? [:]
        let stream = outbound["streamSettings"] as? [String: Any] ?? [:]

        let server: Server?
        switch proto {
        case "vless":
            server = parseVLESS(settings: settings, stream: stream, remark: remark)
        case "trojan":
            server = parseTrojan(settings: settings, stream: stream, remark: remark)
        case "shadowsocks":
            server = parseShadowsocks(settings: settings, remark: remark)
        case "hysteria", "hysteria2":
            server = parseHysteria(settings: settings, stream: stream, remark: remark)
        default:
            server = nil
        }
        guard var result = server else { return nil }
        result.descriptionText = description
        return result
    }

    // MARK: - VLESS

    private static func parseVLESS(settings: [String: Any], stream: [String: Any], remark: String) -> Server? {
        guard let vnext = (settings["vnext"] as? [[String: Any]])?.first,
              let host = vnext["address"] as? String,
              let port = intValue(vnext["port"]),
              let user = (vnext["users"] as? [[String: Any]])?.first,
              let uuid = user["id"] as? String else { return nil }

        guard let transport = parseTransport(stream) else { return nil } // xhttp и пр. → пропуск
        let config = VLESSConfig(
            uuid: uuid,
            flow: (user["flow"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            tls: parseTLS(stream, defaultSNI: host),
            transport: transport
        )
        return makeServer(remark: remark, host: host, port: port, kind: .vless(config))
    }

    // MARK: - Trojan

    private static func parseTrojan(settings: [String: Any], stream: [String: Any], remark: String) -> Server? {
        guard let server = (settings["servers"] as? [[String: Any]])?.first,
              let host = server["address"] as? String,
              let port = intValue(server["port"]),
              let password = server["password"] as? String else { return nil }

        guard let transport = parseTransport(stream) else { return nil }
        var tls = parseTLS(stream, defaultSNI: host)
        if tls.security == .none { tls.security = .tls } // trojan всегда поверх TLS
        let config = TrojanConfig(password: password, tls: tls, transport: transport)
        return makeServer(remark: remark, host: host, port: port, kind: .trojan(config))
    }

    // MARK: - Shadowsocks

    private static func parseShadowsocks(settings: [String: Any], remark: String) -> Server? {
        guard let server = (settings["servers"] as? [[String: Any]])?.first,
              let host = server["address"] as? String,
              let port = intValue(server["port"]),
              let method = server["method"] as? String,
              let password = server["password"] as? String else { return nil }
        let config = ShadowsocksConfig(method: method, password: password)
        return makeServer(remark: remark, host: host, port: port, kind: .shadowsocks(config))
    }

    // MARK: - Hysteria2 (Xray-формат: protocol hysteria, version 2)

    private static func parseHysteria(settings: [String: Any], stream: [String: Any], remark: String) -> Server? {
        guard let host = settings["address"] as? String,
              let port = intValue(settings["port"]) else { return nil }
        let hy = stream["hysteriaSettings"] as? [String: Any] ?? [:]
        let tls = stream["tlsSettings"] as? [String: Any] ?? [:]

        guard let auth = (hy["auth"] as? String) ?? (settings["auth"] as? String), !auth.isEmpty else { return nil }

        var obfsPassword: String?
        if let obfs = hy["obfs"] as? [String: Any] {
            obfsPassword = obfs["password"] as? String
        } else if let obfs = hy["obfs"] as? String, !obfs.isEmpty {
            obfsPassword = obfs
        }

        let config = Hysteria2Config(
            password: auth,
            serverName: (tls["serverName"] as? String) ?? host,
            allowInsecure: (tls["allowInsecure"] as? Bool) ?? false,
            obfsPassword: obfsPassword,
            portRange: hy["ports"] as? String
        )
        return makeServer(remark: remark, host: host, port: port, kind: .hysteria2(config))
    }

    // MARK: - Транспорт и TLS

    /// Возвращает nil для неподдерживаемых транспортов (xhttp/splithttp/quic) — сервер пропускается.
    private static func parseTransport(_ stream: [String: Any]) -> TransportConfig? {
        let network = (stream["network"] as? String)?.lowercased() ?? "tcp"
        switch network {
        case "tcp", "raw", "none":
            return TransportConfig(type: .tcp)
        case "ws", "websocket":
            let ws = stream["wsSettings"] as? [String: Any] ?? [:]
            let host = (ws["headers"] as? [String: Any])?["Host"] as? String
            return TransportConfig(type: .ws, path: ws["path"] as? String, host: host)
        case "grpc", "gun":
            let grpc = stream["grpcSettings"] as? [String: Any] ?? [:]
            return TransportConfig(type: .grpc, serviceName: grpc["serviceName"] as? String)
        case "httpupgrade":
            let hu = stream["httpupgradeSettings"] as? [String: Any] ?? [:]
            return TransportConfig(type: .httpupgrade, path: hu["path"] as? String, host: hu["host"] as? String)
        default:
            // xhttp, splithttp, quic, kcp — sing-box их так не поддерживает
            return nil
        }
    }

    private static func parseTLS(_ stream: [String: Any], defaultSNI: String) -> TLSConfig {
        let security = (stream["security"] as? String)?.lowercased() ?? "none"
        switch security {
        case "reality":
            let r = stream["realitySettings"] as? [String: Any] ?? [:]
            return TLSConfig(
                security: .reality,
                serverName: (r["serverName"] as? String) ?? defaultSNI,
                fingerprint: (r["fingerprint"] as? String) ?? "chrome",
                realityPublicKey: r["publicKey"] as? String,
                realityShortID: r["shortId"] as? String
            )
        case "tls", "xtls":
            let t = stream["tlsSettings"] as? [String: Any] ?? [:]
            return TLSConfig(
                security: .tls,
                serverName: (t["serverName"] as? String) ?? defaultSNI,
                alpn: (t["alpn"] as? [String]) ?? [],
                fingerprint: t["fingerprint"] as? String,
                allowInsecure: (t["allowInsecure"] as? Bool) ?? false
            )
        default:
            return TLSConfig(security: .none)
        }
    }

    private static func makeServer(remark: String, host: String, port: Int, kind: ServerKind) -> Server {
        // Имя оставляем полным (без флага) — оно информативно целиком,
        // а вкладка определяется тематически по ключевым словам.
        return Server(
            name: ShareLinkParser.stripFlagEmoji(remark),
            rawName: remark,
            group: ShareLinkParser.detectCategory(remark),
            countryCode: ShareLinkParser.detectCountry(remark),
            host: host,
            port: port,
            kind: kind
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let d = value as? Double { return Int(d) }
        return nil
    }
}
