import XCTest
@testable import ClevVPNKit

#if os(macOS)
/// Валидация сгенерированных конфигов настоящим ядром: `sing-box check`.
/// Запускается только на macOS и только если ядро установлено (brew install sing-box).
final class ConfigValidationTests: XCTestCase {

    private var corePath: String? {
        ["/opt/homebrew/bin/sing-box", "/usr/local/bin/sing-box"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func makeServers() -> [Server] {
        let links = """
        vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?type=tcp&security=reality&pbk=grPz0BUKgAftfxb1WBWtDF5eXPGXW9jVJ5rV2AC1WBU&fp=chrome&sni=yahoo.com&sid=01ab&flow=xtls-rprx-vision#Reality
        vless://b831381d-6324-4d53-ad4f-8cda48b30812@ws.example.com:2053?type=ws&security=tls&sni=cdn.example.com&host=cdn.example.com&path=%2Fws#WS
        hysteria2://letmein@9.9.9.9:8443?sni=hy.example.com&obfs=salamander&obfs-password=obfs123&mport=20000-30000#Hysteria2
        trojan://password@5.6.7.8:443?sni=site.com#Trojan
        ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpzZWNyZXQ=@3.3.3.3:8388#SS
        """
        return ShareLinkParser.parseSubscriptionContent(links)
    }

    private func check(_ builder: SingBoxConfigBuilder, core: String, name: String) throws {
        let json = try builder.buildTunnelConfigJSON()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clevvpn-test-\(name).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: core)
        process.arguments = ["check", "-c", url.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let stderr = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, "config '\(name)' rejected by sing-box: \(stderr)")
    }

    func testGeneratedConfigsPassRealCoreCheck() throws {
        guard let core = corePath else {
            throw XCTSkip("sing-box not installed")
        }
        let servers = makeServers()
        XCTAssertEqual(servers.count, 5)

        let appRules = [
            AppRule(name: "Telegram", bundlePath: "/Applications/Telegram.app"),
            AppRule(name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app")
        ]
        let customRules = [
            RoutingRule(value: "sberbank.ru", matcher: .domainSuffix, target: .direct),
            RoutingRule(value: "10.0.0.0/8", matcher: .ipCIDR, target: .proxy)
        ]

        // Каждый протокол по отдельности, глобальный режим
        for (index, server) in servers.enumerated() {
            try check(SingBoxConfigBuilder(server: server, routingMode: .global, customRules: []),
                      core: core, name: "single-\(index)")
        }
        // Умный режим + свои правила
        try check(SingBoxConfigBuilder(server: servers[0], routingMode: .smart, customRules: customRules),
                  core: core, name: "smart-custom")
        // Авто (urltest-группа из всех серверов)
        try check(SingBoxConfigBuilder(servers: servers, autoSelect: true, routingMode: .smart, customRules: []),
                  core: core, name: "auto")
        // Правила приложений: выбранные мимо VPN
        try check(SingBoxConfigBuilder(servers: servers, autoSelect: false, routingMode: .global,
                                       customRules: customRules, appRules: appRules, appRoutingMode: .bypassSelected),
                  core: core, name: "apps-bypass")
        // Правила приложений: только выбранные через VPN
        try check(SingBoxConfigBuilder(servers: servers, autoSelect: true, routingMode: .global,
                                       customRules: [], appRules: appRules, appRoutingMode: .onlySelected),
                  core: core, name: "apps-only")
    }
}
#endif
