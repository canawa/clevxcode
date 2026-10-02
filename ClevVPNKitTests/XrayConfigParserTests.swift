import XCTest
@testable import ClevVPNKit

final class XrayConfigParserTests: XCTestCase {

    /// Профили в формате, который реально отдаёт панель lavivas.org (Remnawave/Happ).
    private let sample = """
    [
      {
        "remarks": "🇩🇪 Германия | Ультра⚡",
        "outbounds": [
          {
            "tag": "proxy",
            "protocol": "vless",
            "settings": { "vnext": [ { "address": "germ.lavivas.org", "port": 7443,
              "users": [ { "id": "aaa9f317-78a8-42a6-99f2-b5e94b47eba6", "encryption": "none", "flow": "xtls-rprx-vision" } ] } ] },
            "streamSettings": { "network": "tcp", "security": "tls",
              "tlsSettings": { "serverName": "germ.lavivas.org", "fingerprint": "firefox", "alpn": ["h2","http/1.1"] } }
          },
          { "tag": "direct", "protocol": "freedom" }
        ]
      },
      {
        "remarks": "🇳🇱 Нидерланды 2 | Ультра⚡",
        "outbounds": [ {
          "tag": "proxy", "protocol": "hysteria",
          "settings": { "address": "dedik.lavivas.org", "port": 9443, "version": 2 },
          "streamSettings": { "network": "hysteria",
            "hysteriaSettings": { "version": 2, "auth": "aaa9f317-78a8-42a6-99f2-b5e94b47eba6" },
            "security": "tls", "tlsSettings": { "serverName": "dedik.lavivas.org", "alpn": ["h3"] } }
        } ]
      },
      {
        "remarks": "🇷🇺 Youtube и Instagram",
        "outbounds": [ {
          "tag": "proxy", "protocol": "vless",
          "settings": { "vnext": [ { "address": "reality.lavivas.org", "port": 443,
            "users": [ { "id": "uuid-reality", "flow": "xtls-rprx-vision" } ] } ] },
          "streamSettings": { "network": "tcp", "security": "reality",
            "realitySettings": { "serverName": "m.vk.com", "publicKey": "K77asb8hInjx4LNYkx9t-kR1_4w7zCEypRI5tqQvB2M", "fingerprint": "chrome", "shortId": "ab12" } }
        } ]
      },
      {
        "remarks": "🇪🇺 Обход глушилок 13 | Моб. интернет",
        "outbounds": [ {
          "tag": "proxy", "protocol": "trojan",
          "settings": { "servers": [ { "address": "select.lavivas.org", "port": 8443, "password": "HcfMU4mTkMsBLJeySBATZZS34qLFFEUo" } ] },
          "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "grpc" },
            "security": "tls", "tlsSettings": { "serverName": "select.lavivas.org" } }
        } ]
      },
      {
        "remarks": "🇺🇸 xhttp server",
        "outbounds": [ {
          "tag": "proxy", "protocol": "vless",
          "settings": { "vnext": [ { "address": "xh.lavivas.org", "port": 443, "users": [ { "id": "u" } ] } ] },
          "streamSettings": { "network": "xhttp", "security": "tls", "tlsSettings": { "serverName": "xh.lavivas.org" } }
        } ]
      }
    ]
    """

    func testDetectsXrayFormat() {
        XCTAssertTrue(XrayConfigParser.looksLikeXrayJSON(sample))
        XCTAssertFalse(XrayConfigParser.looksLikeXrayJSON("vless://x@1.2.3.4:443#a"))
    }

    func testParsesAllSupportedProtocols() throws {
        let servers = XrayConfigParser.parse(sample)
        // 5 профилей, но xhttp не поддерживается — остаётся 4
        XCTAssertEqual(servers.count, 4)

        let germany = try XCTUnwrap(servers.first { $0.host == "germ.lavivas.org" })
        XCTAssertEqual(germany.protocolType, .vless)
        XCTAssertEqual(germany.port, 7443)
        XCTAssertEqual(germany.countryCode, "DE")
        XCTAssertEqual(germany.group, "Скорость") // «Ультра» → категория Скорость
        guard case .vless(let vlessConfig) = germany.kind else { return XCTFail() }
        XCTAssertEqual(vlessConfig.flow, "xtls-rprx-vision")
        XCTAssertEqual(vlessConfig.tls.security, .tls)
        XCTAssertEqual(vlessConfig.tls.fingerprint, "firefox")
    }

    func testHysteria2FromXray() throws {
        let servers = XrayConfigParser.parse(sample)
        let nl = try XCTUnwrap(servers.first { $0.host == "dedik.lavivas.org" })
        XCTAssertEqual(nl.protocolType, .hysteria2)
        guard case .hysteria2(let config) = nl.kind else { return XCTFail() }
        XCTAssertEqual(config.password, "aaa9f317-78a8-42a6-99f2-b5e94b47eba6")
        XCTAssertEqual(config.serverName, "dedik.lavivas.org")
    }

    func testRealityFromXray() throws {
        let servers = XrayConfigParser.parse(sample)
        let ru = try XCTUnwrap(servers.first { $0.host == "reality.lavivas.org" })
        XCTAssertEqual(ru.group, "Ютуб") // «Youtube» → категория Ютуб
        guard case .vless(let config) = ru.kind else { return XCTFail() }
        XCTAssertEqual(config.tls.security, .reality)
        XCTAssertEqual(config.tls.realityPublicKey, "K77asb8hInjx4LNYkx9t-kR1_4w7zCEypRI5tqQvB2M")
        XCTAssertEqual(config.tls.serverName, "m.vk.com")
        XCTAssertEqual(config.tls.realityShortID, "ab12")
    }

    func testTrojanGrpcFromXray() throws {
        let servers = XrayConfigParser.parse(sample)
        let bypass = try XCTUnwrap(servers.first { $0.host == "select.lavivas.org" })
        XCTAssertEqual(bypass.protocolType, .trojan)
        XCTAssertEqual(bypass.group, "Обходы")
        guard case .trojan(let config) = bypass.kind else { return XCTFail() }
        XCTAssertEqual(config.password, "HcfMU4mTkMsBLJeySBATZZS34qLFFEUo")
        XCTAssertEqual(config.transport.type, .grpc)
        XCTAssertEqual(config.transport.serviceName, "grpc")
    }

    func testCategoryDetection() {
        XCTAssertEqual(ShareLinkParser.detectCategory("🇪🇺 Авто | Европа | WIFI"), "Авто")
        XCTAssertEqual(ShareLinkParser.detectCategory("Обход глушилок"), "Обходы")
        XCTAssertEqual(ShareLinkParser.detectCategory("🇷🇺 Youtube"), "Ютуб")
        XCTAssertNil(ShareLinkParser.detectCategory("🇫🇮 Финляндия"))
    }
}
