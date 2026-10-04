import XCTest
@testable import ClevVPNKit

final class ShareLinkParserTests: XCTestCase {

    // MARK: - VLESS

    func testVLESSRealityLink() throws {
        let link = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?type=tcp&security=reality&pbk=SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc&fp=chrome&sni=yahoo.com&sid=0123abcd&flow=xtls-rprx-vision#Premium%20%7C%20%F0%9F%87%A9%F0%9F%87%AA%20Frankfurt"
        let server = try XCTUnwrap(ShareLinkParser.parseLink(link))

        XCTAssertEqual(server.protocolType, .vless)
        XCTAssertEqual(server.host, "1.2.3.4")
        XCTAssertEqual(server.port, 443)
        XCTAssertEqual(server.group, "Premium")
        // Флаг из имени уходит в countryCode, отображаемое имя — без эмодзи
        XCTAssertEqual(server.name, "Frankfurt")
        XCTAssertEqual(server.countryCode, "DE")

        guard case .vless(let config) = server.kind else { return XCTFail("expected vless") }
        XCTAssertEqual(config.uuid, "b831381d-6324-4d53-ad4f-8cda48b30811")
        XCTAssertEqual(config.flow, "xtls-rprx-vision")
        XCTAssertEqual(config.tls.security, .reality)
        XCTAssertEqual(config.tls.serverName, "yahoo.com")
        XCTAssertEqual(config.tls.realityPublicKey, "SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc")
        XCTAssertEqual(config.tls.realityShortID, "0123abcd")
        XCTAssertEqual(config.tls.fingerprint, "chrome")
        XCTAssertEqual(config.transport.type, .tcp)
    }

    func testVLESSWebSocketLink() throws {
        let link = "vless://uuid-123@example.com:2053?type=ws&security=tls&sni=cdn.example.com&host=cdn.example.com&path=%2Fws#WS%20Server"
        let server = try XCTUnwrap(ShareLinkParser.parseLink(link))

        guard case .vless(let config) = server.kind else { return XCTFail("expected vless") }
        XCTAssertEqual(config.transport.type, .ws)
        XCTAssertEqual(config.transport.path, "/ws")
        XCTAssertEqual(config.transport.host, "cdn.example.com")
        XCTAssertEqual(config.tls.security, .tls)
        XCTAssertNil(server.group)
    }

    // MARK: - Trojan

    func testTrojanLinkDefaultsToTLS() throws {
        let link = "trojan://p%40ssword@5.6.7.8:443?sni=site.com#%F0%9F%87%B3%F0%9F%87%B1%20Amsterdam"
        let server = try XCTUnwrap(ShareLinkParser.parseLink(link))

        XCTAssertEqual(server.countryCode, "NL")
        guard case .trojan(let config) = server.kind else { return XCTFail("expected trojan") }
        XCTAssertEqual(config.password, "p@ssword")
        XCTAssertEqual(config.tls.security, .tls)
        XCTAssertEqual(config.tls.serverName, "site.com")
    }

    // MARK: - Hysteria2

    func testHysteria2Link() throws {
        let link = "hysteria2://letmein@9.9.9.9:8443?sni=hy.example.com&insecure=1&obfs=salamander&obfs-password=obfs123&mport=20000-30000#Speed%20%7C%20%F0%9F%87%AB%F0%9F%87%AE%20Helsinki"
        let server = try XCTUnwrap(ShareLinkParser.parseLink(link))

        XCTAssertEqual(server.protocolType, .hysteria2)
        XCTAssertEqual(server.group, "Speed")
        XCTAssertEqual(server.countryCode, "FI")

        guard case .hysteria2(let config) = server.kind else { return XCTFail("expected hysteria2") }
        XCTAssertEqual(config.password, "letmein")
        XCTAssertEqual(config.serverName, "hy.example.com")
        XCTAssertTrue(config.allowInsecure)
        XCTAssertEqual(config.obfsPassword, "obfs123")
        XCTAssertEqual(config.portRange, "20000:30000")
    }

    func testHy2SchemeAlias() {
        let link = "hy2://pass@1.1.1.1:443#test"
        XCTAssertNotNil(ShareLinkParser.parseLink(link))
    }

    // MARK: - Shadowsocks

    func testShadowsocksSIP002() throws {
        // base64url("chacha20-ietf-poly1305:secret")
        let userinfo = Data("chacha20-ietf-poly1305:secret".utf8).base64EncodedString()
        let link = "ss://\(userinfo)@3.3.3.3:8388#SS%20Server"
        let server = try XCTUnwrap(ShareLinkParser.parseLink(link))

        guard case .shadowsocks(let config) = server.kind else { return XCTFail("expected ss") }
        XCTAssertEqual(config.method, "chacha20-ietf-poly1305")
        XCTAssertEqual(config.password, "secret")
    }

    // MARK: - Подписка целиком

    func testBase64SubscriptionContent() {
        let links = """
        vless://uuid@1.2.3.4:443?security=tls#Server1
        trojan://pass@5.6.7.8:443#Server2
        """
        let encoded = Data(links.utf8).base64EncodedString()
        let servers = ShareLinkParser.parseSubscriptionContent(encoded)
        XCTAssertEqual(servers.count, 2)
    }

    func testPlainSubscriptionContentSkipsGarbage(){
        let content = """
        vless://uuid@1.2.3.4:443?security=tls#OK
        not-a-link
        unknown://xxx@1.1.1.1:1#skip
        """
        let servers = ShareLinkParser.parseSubscriptionContent(content)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.name, "OK")
    }

    func testStableServerID() throws {
        let link = "vless://uuid@1.2.3.4:443?security=tls#Name"
        let a = try XCTUnwrap(ShareLinkParser.parseLink(link))
        let b = try XCTUnwrap(ShareLinkParser.parseLink(link))
        XCTAssertEqual(a.id, b.id)
    }

    // MARK: - Определение страны

    func testCountryFromFlagEmoji() {
        XCTAssertEqual(ShareLinkParser.detectCountry("🇩🇪 Frankfurt"), "DE")
        XCTAssertEqual(ShareLinkParser.detectCountry("Сервер 🇷🇺"), "RU")
    }

    func testCountryFromText() {
        XCTAssertEqual(ShareLinkParser.detectCountry("Германия — Франкфурт"), "DE")
        XCTAssertEqual(ShareLinkParser.detectCountry("Netherlands 01"), "NL")
        XCTAssertNil(ShareLinkParser.detectCountry("Server 42"))
    }

    func testFlagEmojiRendering() throws {
        let link = "vless://uuid@1.2.3.4:443?security=tls#%F0%9F%87%A9%F0%9F%87%AA%20Berlin"
        let server = try XCTUnwrap(ShareLinkParser.parseLink(link))
        XCTAssertEqual(server.flagEmoji, "🇩🇪")
    }
}

final class SubscriptionUserInfoTests: XCTestCase {
    func testParseFullHeader() {
        let info = SubscriptionUserInfo.parse("upload=1024; download=2048; total=10737418240; expire=1767225600")
        XCTAssertEqual(info.uploadBytes, 1024)
        XCTAssertEqual(info.downloadBytes, 2048)
        XCTAssertEqual(info.totalBytes, 10_737_418_240)
        XCTAssertEqual(info.usedBytes, 3072)
        XCTAssertEqual(info.expiresAt, Date(timeIntervalSince1970: 1_767_225_600))
    }

    func testParsePartialHeader() {
        let info = SubscriptionUserInfo.parse("upload=0; download=555")
        XCTAssertEqual(info.usedBytes, 555)
        XCTAssertNil(info.totalBytes)
        XCTAssertNil(info.expiresAt)
    }
}
