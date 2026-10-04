import XCTest
@testable import ClevVPNKit

final class SingBoxConfigBuilderTests: XCTestCase {

    private func makeVLESSServer() -> Server {
        Server(
            name: "🇩🇪 Frankfurt",
            rawName: "Premium | 🇩🇪 Frankfurt",
            group: "Premium",
            countryCode: "DE",
            host: "1.2.3.4",
            port: 443,
            kind: .vless(VLESSConfig(
                uuid: "test-uuid",
                flow: "xtls-rprx-vision",
                tls: TLSConfig(security: .reality,
                               serverName: "yahoo.com",
                               fingerprint: "chrome",
                               realityPublicKey: "pbk",
                               realityShortID: "sid"),
                transport: TransportConfig(type: .tcp)
            ))
        )
    }

    private func makeHysteria2Server() -> Server {
        Server(
            name: "🇫🇮 Helsinki",
            rawName: "🇫🇮 Helsinki",
            countryCode: "FI",
            host: "9.9.9.9",
            port: 8443,
            kind: .hysteria2(Hysteria2Config(
                password: "letmein",
                serverName: "hy.example.com",
                obfsPassword: "obfs123",
                portRange: "20000:30000"
            ))
        )
    }

    func testTunnelConfigStructure() throws {
        let builder = SingBoxConfigBuilder(server: makeVLESSServer(), routingMode: .smart, customRules: [])
        let config = builder.buildTunnelConfig()

        XCTAssertNotNil(config["log"])
        XCTAssertNotNil(config["dns"])
        XCTAssertNotNil(config["route"])

        let inbounds = try XCTUnwrap(config["inbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.first?["type"] as? String, "tun")
        XCTAssertEqual(inbounds.first?["auto_route"] as? Bool, true)

        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.count, 2)
        XCTAssertEqual(outbounds[0]["tag"] as? String, "proxy")
        XCTAssertEqual(outbounds[1]["type"] as? String, "direct")
    }

    func testVLESSRealityOutbound() throws {
        let out = SingBoxConfigBuilder.outbound(for: makeVLESSServer(), tag: "proxy")
        XCTAssertEqual(out["type"] as? String, "vless")
        XCTAssertEqual(out["uuid"] as? String, "test-uuid")
        XCTAssertEqual(out["flow"] as? String, "xtls-rprx-vision")

        let tls = try XCTUnwrap(out["tls"] as? [String: Any])
        XCTAssertEqual(tls["server_name"] as? String, "yahoo.com")
        let reality = try XCTUnwrap(tls["reality"] as? [String: Any])
        XCTAssertEqual(reality["public_key"] as? String, "pbk")
        let utls = try XCTUnwrap(tls["utls"] as? [String: Any])
        XCTAssertEqual(utls["fingerprint"] as? String, "chrome")
    }

    func testHysteria2Outbound() throws {
        let out = SingBoxConfigBuilder.outbound(for: makeHysteria2Server(), tag: "proxy")
        XCTAssertEqual(out["type"] as? String, "hysteria2")
        XCTAssertEqual(out["password"] as? String, "letmein")
        // При port hopping одиночный порт заменяется диапазоном
        XCTAssertNil(out["server_port"])
        XCTAssertEqual(out["server_ports"] as? [String], ["20000:30000"])

        let obfs = try XCTUnwrap(out["obfs"] as? [String: Any])
        XCTAssertEqual(obfs["type"] as? String, "salamander")

        let tls = try XCTUnwrap(out["tls"] as? [String: Any])
        XCTAssertEqual(tls["alpn"] as? [String], ["h3"])
    }

    func testSmartModeAddsRuRules() throws {
        let builder = SingBoxConfigBuilder(server: makeVLESSServer(), routingMode: .smart, customRules: [])
        let route = try XCTUnwrap(builder.buildTunnelConfig()["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])

        // Умный режим направляет российские домены напрямую по суффиксам.
        // (remote rule_set geoip-ru убран ради быстрого старта — он качался с GitHub.)
        XCTAssertTrue(rules.contains { ($0["domain_suffix"] as? [String])?.contains(".ru") == true })
    }

    func testGlobalModeHasNoRuBypass() throws {
        let builder = SingBoxConfigBuilder(server: makeVLESSServer(), routingMode: .global, customRules: [])
        let route = try XCTUnwrap(builder.buildTunnelConfig()["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])

        XCTAssertFalse(rules.contains { ($0["domain_suffix"] as? [String])?.contains(".ru") == true })
        XCTAssertEqual(route["final"] as? String, "proxy")
    }

    func testCustomRulesHavePriority() throws {
        let rules = [
            RoutingRule(value: "sberbank.ru", matcher: .domainSuffix, target: .direct),
            RoutingRule(value: "10.0.0.0/8", matcher: .ipCIDR, target: .proxy),
            RoutingRule(value: "disabled.com", matcher: .domainSuffix, target: .direct, isEnabled: false)
        ]
        let builder = SingBoxConfigBuilder(server: makeVLESSServer(), routingMode: .custom, customRules: rules)
        let route = try XCTUnwrap(builder.buildTunnelConfig()["route"] as? [String: Any])
        let routeRules = try XCTUnwrap(route["rules"] as? [[String: Any]])

        XCTAssertTrue(routeRules.contains {
            ($0["domain_suffix"] as? [String]) == ["sberbank.ru"] && $0["outbound"] as? String == "direct"
        })
        XCTAssertTrue(routeRules.contains {
            ($0["ip_cidr"] as? [String]) == ["10.0.0.0/8"] && $0["outbound"] as? String == "proxy"
        })
        // Выключенные правила не попадают в конфиг
        XCTAssertFalse(routeRules.contains { ($0["domain_suffix"] as? [String]) == ["disabled.com"] })
    }

    func testConfigSerializesToValidJSON() throws {
        let builder = SingBoxConfigBuilder(server: makeHysteria2Server(), routingMode: .smart,
                                           customRules: [RoutingRule(value: "example.com", matcher: .domainSuffix, target: .direct)])
        let json = try builder.buildTunnelConfigJSON()
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        XCTAssertNotNil(parsed as? [String: Any])
    }

    func testPingConfigContainsAllServers() throws {
        let config = SingBoxConfigBuilder.buildPingConfig(servers: [makeVLESSServer(), makeHysteria2Server()], clashPort: 19090)
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.count, 3) // 2 сервера + direct
        XCTAssertNil(config["inbounds"]) // без TUN
    }
}
