import Foundation
import AppKit

/// Обнаружение другого активного VPN-клиента (Happ, Incy, v2ray, Clash и т.п.).
/// Проверять имеет смысл, только когда наш собственный туннель выключен —
/// иначе наш sing-box был бы принят за чужой.
enum ConflictDetector {

    struct Conflict: Equatable {
        /// Человекочитаемое имя найденного клиента ("Happ", "v2rayN"…).
        let name: String
    }

    /// GUI-приложения VPN-клиентов: часть имени bundleIdentifier или названия.
    private static let knownApps: [(needle: String, label: String)] = [
        ("happ", "Happ"),
        ("incy", "Incy"),
        ("v2box", "V2Box"),
        ("v2rayu", "V2RayU"),
        ("v2rayxs", "V2RayXS"),
        ("foxray", "FoxRay"),
        ("nekoray", "Nekoray"),
        ("nekobox", "NekoBox"),
        ("sing-box", "sing-box"),
        ("sfm", "sing-box"),
        ("clashx", "ClashX"),
        ("clash-verge", "Clash Verge"),
        ("clashverge", "Clash Verge"),
        ("mihomo", "Mihomo"),
        ("stash", "Stash"),
        ("surge", "Surge"),
        ("streisand", "Streisand"),
        ("hiddify", "Hiddify"),
        ("karing", "Karing"),
        ("outline", "Outline"),
        ("mullvad", "Mullvad"),
        ("protonvpn", "ProtonVPN"),
        ("nordvpn", "NordVPN"),
        ("expressvpn", "ExpressVPN"),
        ("windscribe", "Windscribe"),
        ("wireguard", "WireGuard"),
        ("tunnelblick", "Tunnelblick"),
        ("openvpn", "OpenVPN"),
        ("amneziavpn", "AmneziaVPN"),
        ("amnezia", "Amnezia")
    ]

    /// CLI-ядра ЧУЖИХ VPN (без GUI). ВАЖНО: sing-box сюда НЕ входит — это наше
    /// ядро, и по имени процесса его не отличить от нашего собственного/тестового,
    /// поэтому активность туннеля определяем только по маршруту (defaultRouteViaVPN).
    private static let knownCores: Set<String> = [
        "xray", "v2ray", "mihomo", "clash", "clash-meta",
        "tun2socks", "wireguard-go",
        "naive", "gost", "trojan", "trojan-go",
        "tuic", "tuic-client", "juicity", "juicity-client"
    ]

    /// Возвращает конфликт, только если ДРУГОЙ VPN реально активен (заворачивает
    /// трафик через туннель) — а не просто запущено приложение в трее.
    /// Когда включён наш собственный туннель, проверку пропускаем.
    static func detect(ownTunnelActive: Bool) -> Conflict? {
        guard !ownTunnelActive else { return nil }

        // Сигнал 1: маршрут по умолчанию идёт через VPN-интерфейс (utun/ipsec/ppp).
        // Это и есть факт «весь трафик заворачивается в чужой туннель».
        let tunnelActive = defaultRouteViaVPN()
        // Сигнал 2: работает известное VPN-ядро (xray/sing-box/…) — туннель тоже активен.
        let coreName = detectRunningCore()

        guard tunnelActive || coreName != nil else { return nil }

        // Имя для показа: ядро → запущенное известное приложение → общее.
        let name = coreName
            ?? runningAppName()
            ?? String(localized: "another VPN", bundle: .main)
        return Conflict(name: name)
    }

    /// Маршрут по умолчанию (IPv4/IPv6) через туннельный интерфейс.
    private static func defaultRouteViaVPN() -> Bool {
        for family in ["-inet", "-inet6"] {
            guard let iface = routeInterface(family: family) else { continue }
            if iface.hasPrefix("utun") || iface.hasPrefix("ipsec")
                || iface.hasPrefix("ppp") || iface.hasPrefix("tap") || iface.hasPrefix("tun") {
                return true
            }
        }
        return false
    }

    private static func routeInterface(family: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", family, "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                return trimmed.replacingOccurrences(of: "interface:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Имя запущенного известного VPN-приложения (для подписи баннера).
    private static func runningAppName() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy != .prohibited else { continue }
            let bundle = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            if bundle == "com.clevvpn.mac" { continue }
            for entry in knownApps where bundle.contains(entry.needle) || name.contains(entry.needle) {
                return entry.label
            }
        }
        return nil
    }

    /// Имя работающего VPN-ядра (без GUI). Вызывается только когда наш туннель
    /// выключен, поэтому свой sing-box сюда не попадает.
    private static func detectRunningCore() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)

        for line in output.split(separator: "\n") {
            let comm = String(line).split(separator: "/").last.map(String.init) ?? String(line)
            let name = comm.lowercased()
            if knownCores.contains(name) {
                return comm
            }
        }
        return nil
    }
}
