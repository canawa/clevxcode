import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Загрузка и разбор подписки Remnawave по ссылке пользователя.
public struct SubscriptionClient: Sendable {
    /// Мимикрируем под Happ: Remnawave отдаёт по этому UA свой Happ-шаблон
    /// (ссылки vless/trojan/hysteria2/ss) и корректно применяет лимит устройств.
    public static let userAgent = "Happ/3.13.0"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(from urlString: String) async throws -> Subscription {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil else {
            throw SubscriptionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        // Как и Happ, передаём идентификатор устройства — Remnawave считает по нему
        // лимит устройств на подписку
        request.setValue(Self.deviceID, forHTTPHeaderField: "X-Hwid")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SubscriptionError.httpError(-1) }
        guard (200..<300).contains(http.statusCode) else { throw SubscriptionError.httpError(http.statusCode) }
        guard let body = String(data: data, encoding: .utf8) else { throw SubscriptionError.emptyOrUnparsable }

        // Панель может отдавать Xray-JSON (шаблон Happ) или список share-ссылок.
        let servers: [Server]
        if XrayConfigParser.looksLikeXrayJSON(body) {
            servers = XrayConfigParser.parse(body)
        } else {
            servers = ShareLinkParser.parseSubscriptionContent(body)
        }
        guard !servers.isEmpty else { throw SubscriptionError.emptyOrUnparsable }

        return Subscription(
            servers: servers,
            title: decodedHeader(http, "profile-title"),
            userInfo: header(http, "subscription-userinfo").map(SubscriptionUserInfo.parse),
            announce: decodedHeader(http, "announce"),
            supportURL: header(http, "support-url"),
            updatedAt: Date(),
            updateIntervalHours: header(http, "profile-update-interval").flatMap { Int($0) }
        )
    }

    /// Стабильный идентификатор устройства для X-Hwid.
    /// identifierForVendor с запасным UUID, который живёт в App Group.
    public static var deviceID: String {
        #if canImport(UIKit)
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            return vendorID
        }
        #endif
        let key = "deviceHWID"
        if let stored = SharedStore.defaults.string(forKey: key) {
            return stored
        }
        let generated = UUID().uuidString
        SharedStore.defaults.set(generated, forKey: key)
        return generated
    }

    private func header(_ response: HTTPURLResponse, _ name: String) -> String? {
        response.value(forHTTPHeaderField: name)?.trimmingCharacters(in: .whitespaces)
    }

    /// Заголовки Remnawave могут быть в виде "base64:<данные>".
    private func decodedHeader(_ response: HTTPURLResponse, _ name: String) -> String? {
        guard let raw = header(response, name), !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("base64:") {
            let payload = String(raw.dropFirst("base64:".count))
            return ShareLinkParser.base64Decode(payload) ?? raw
        }
        return raw
    }
}
