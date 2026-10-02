import Foundation
import ClevVPNKit

/// Kill Switch на macOS через системный файрвол pf: блокирует ВЕСЬ исходящий
/// трафик, кроме соединений к VPN-серверам, локальной сети и loopback.
/// Правила pf переживают падение процесса sing-box — поэтому при внезапном
/// обрыве VPN интернет остаётся заблокированным и реальный IP не утекает.
enum KillSwitch {

    private static let anchorName = "clevvpn"
    private static var rulesURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("clevvpn-killswitch.pf")
    }

    /// Включает блокировку. `serverHosts` — хосты серверов туннеля (резолвятся в IP,
    /// чтобы туннель мог подключаться/переподключаться при активном kill switch).
    /// Возвращает true при успехе.
    @discardableResult
    static func enable(serverHosts: [String]) -> Bool {
        let ips = serverHosts.compactMap(resolveIP).uniqued()
        let rules = buildRules(serverIPs: ips)
        guard (try? rules.write(to: rulesURL, atomically: true, encoding: .utf8)) != nil else { return false }
        // Загружаем правила и включаем pf
        return runPfctl(["-f", rulesURL.path]) && runPfctl(["-e"])
    }

    /// Снимает блокировку (выключает pf и очищает наши правила).
    @discardableResult
    static func disable() -> Bool {
        let flushed = runPfctl(["-F", "all"])
        let disabled = runPfctl(["-d"])
        return flushed || disabled
    }

    /// Активен ли kill switch (pf включён с нашими правилами).
    static func isActive() -> Bool {
        FileManager.default.fileExists(atPath: rulesURL.path) && pfEnabled()
    }

    // MARK: - Правила pf

    private static func buildRules(serverIPs: [String]) -> String {
        var lines: [String] = []
        // Локальная сеть и loopback — всегда разрешены (чтобы не оторвать LAN/принтеры/AirDrop)
        let localNets = ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12",
                         "192.168.0.0/16", "169.254.0.0/16", "224.0.0.0/4", "255.255.255.255/32"]
        if !serverIPs.isEmpty {
            lines.append("table <vpnservers> persist { \(serverIPs.joined(separator: ", ")) }")
        }
        lines.append("table <localnets> persist { \(localNets.joined(separator: ", ")) }")
        lines.append("set block-policy drop")
        // Блокируем весь исходящий, затем точечно разрешаем нужное
        lines.append("block drop out all")
        lines.append("pass out quick on lo0 all")
        lines.append("pass out quick to <localnets>")
        if !serverIPs.isEmpty {
            lines.append("pass out quick to <vpnservers>")
        }
        // Разрешаем трафик через туннельные интерфейсы (пользовательский трафик в VPN)
        lines.append("pass out quick on utun0 all")
        for i in 1...15 { lines.append("pass out quick on utun\(i) all") }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - pfctl

    private static func runPfctl(_ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/sbin/pfctl"] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func pfEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/sbin/pfctl", "-s", "info"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).contains("Status: Enabled")
    }

    // MARK: - DNS-резолв

    private static func resolveIP(_ host: String) -> String? {
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return host }
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(res) }
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen,
                          &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: buf)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
