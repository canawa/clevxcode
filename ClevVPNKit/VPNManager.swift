import Foundation
import NetworkExtension

/// Управление системным VPN-туннелем (NETunnelProviderManager).
@MainActor
public final class VPNManager: ObservableObject {
    public static let shared = VPNManager()

    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case invalid
    }

    @Published public private(set) var state: State = .disconnected
    @Published public private(set) var lastError: String?
    /// Момент подключения — для таймера сессии.
    @Published public private(set) var connectedAt: Date?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private static let tunnelBundleID = "com.clevvpn.ios.tunnel"

    private init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            Task { @MainActor in
                self?.apply(status: connection.status)
            }
        }
        Task { await refresh() }
    }

    /// Подхватывает существующий профиль и его статус (например, после перезапуска приложения).
    public func refresh() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first
            if let status = manager?.connection.status {
                apply(status: status)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Пишет конфиг в App Group и стартует туннель.
    /// `autoSelect` — режим «Авто»: ядро само держит самый быстрый из переданных серверов.
    /// `killSwitch` — не пускать трафик мимо туннеля и держать VPN «всегда включённым».
    public func connect(servers: [Server], autoSelect: Bool, routingMode: RoutingMode,
                        customRules: [RoutingRule], killSwitch: Bool) async {
        guard !servers.isEmpty else { return }
        lastError = nil
        do {
            let builder = SingBoxConfigBuilder(servers: servers, autoSelect: autoSelect,
                                               routingMode: routingMode, customRules: customRules)
            let json = try builder.buildTunnelConfigJSON()
            try json.write(to: SharedStore.configURL, atomically: true, encoding: .utf8)

            let displayName = autoSelect ? "Auto" : (servers.first?.name ?? "ClevVPN")
            let manager = try await loadOrCreateManager(serverName: displayName, killSwitch: killSwitch)
            manager.isEnabled = true
            try await manager.saveToPreferences()
            // После первого сохранения профиль нужно перечитать, иначе start падает
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = error.localizedDescription
            state = .disconnected
        }
    }

    #if DEBUG
    /// Демо-подключение без реального туннеля — для просмотра UI и анимации,
    /// когда ядро не собрано / нет платного аккаунта.
    public func startDemo() async {
        lastError = nil
        state = .connecting
        try? await Task.sleep(nanoseconds: 650_000_000)
        connectedAt = Date()
        state = .connected
    }
    public func stopDemo() {
        state = .disconnected
        connectedAt = nil
    }
    #endif

    public func disconnect() async {
        // При активном Kill Switch on-demand переподнял бы туннель сразу после
        // остановки — поэтому сначала снимаем «всегда включён», потом гасим.
        if let manager, manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            try? await manager.saveToPreferences()
        }
        manager?.connection.stopVPNTunnel()
    }

    /// Перезапуск с новым конфигом (смена сервера/маршрутизации на лету).
    public func reconnect(servers: [Server], autoSelect: Bool, routingMode: RoutingMode,
                          customRules: [RoutingRule], killSwitch: Bool) async {
        await disconnect()
        // Даём туннелю корректно остановиться
        try? await Task.sleep(nanoseconds: 700_000_000)
        await connect(servers: servers, autoSelect: autoSelect, routingMode: routingMode,
                      customRules: customRules, killSwitch: killSwitch)
    }

    private func loadOrCreateManager(serverName: String, killSwitch: Bool) async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleID
        proto.serverAddress = serverName
        // Kill Switch: гнать ВЕСЬ трафик в туннель (без утечек), но не рвать LAN.
        proto.includeAllNetworks = killSwitch
        proto.excludeLocalNetworks = true
        if #available(iOS 14.2, *) { proto.enforceRoutes = killSwitch }

        manager.protocolConfiguration = proto
        manager.localizedDescription = "ClevVPN"

        // Kill Switch: «всегда включён» — при обрыве система сама переподнимает
        // туннель и не выпускает трафик наружу до его восстановления.
        manager.isOnDemandEnabled = killSwitch
        if killSwitch {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = [rule]
        } else {
            manager.onDemandRules = nil
        }

        self.manager = manager
        return manager
    }

    private func apply(status: NEVPNStatus) {
        switch status {
        case .connected:
            state = .connected
            if connectedAt == nil { connectedAt = Date() }
        case .connecting, .reasserting:
            state = .connecting
        case .disconnecting:
            state = .disconnecting
        case .disconnected, .invalid:
            state = .disconnected
            connectedAt = nil
        @unknown default:
            state = .invalid
            connectedAt = nil
        }
    }
}
