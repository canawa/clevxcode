import Foundation
import SwiftUI
import Combine
import ClevVPNKit

/// Общее состояние приложения: подписка, серверы, выбор, настройки.
@MainActor
final class AppState: ObservableObject {
    @Published var subscription: ClevVPNKit.Subscription?
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var selectedServerID: String? {
        didSet { SharedStore.selectedServerID = selectedServerID }
    }
    @Published var favorites: Set<String> {
        didSet { SharedStore.favoriteServerIDs = favorites }
    }
    @Published var folders: [ServerFolder] {
        didSet { SharedStore.folders = folders }
    }
    @Published var routingMode: RoutingMode {
        didSet { SharedStore.routingMode = routingMode }
    }
    @Published var customRules: [RoutingRule] {
        didSet { SharedStore.customRules = customRules }
    }
    /// Kill Switch: не выпускать трафик мимо VPN (защита от утечки реального IP).
    @Published var killSwitchEnabled: Bool {
        didSet {
            guard killSwitchEnabled != oldValue else { return }
            SharedStore.killSwitchEnabled = killSwitchEnabled
            // Применяем к активному туннелю переподключением с новыми параметрами.
            Task { await reconnectIfConnected() }
        }
    }
    @Published var tabOrder: [String] {
        didSet { SharedStore.tabOrder = tabOrder }
    }
    @Published var pings: [String: Int]
    @Published var isPinging = false

    let vpn = VPNManager.shared
    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    /// Явный demo: только CLEV_DEMO=1. Без Libbox реальный Connect покажет ошибку
    /// ядра — не подменяем «понарошку», чтобы с настоящей подпиской шёл реальный VPN.
    static let demoMode: Bool = {
        ProcessInfo.processInfo.environment["CLEV_DEMO"] == "1"
    }()
    #else
    static let demoMode = false
    #endif

    init() {
        subscription = SharedStore.cachedSubscription
        selectedServerID = SharedStore.selectedServerID
        favorites = SharedStore.favoriteServerIDs
        folders = SharedStore.folders
        routingMode = SharedStore.routingMode
        customRules = SharedStore.customRules
        killSwitchEnabled = SharedStore.killSwitchEnabled
        tabOrder = SharedStore.tabOrder
        pings = SharedStore.pingResults

        #if DEBUG
        if Self.demoMode {
            let sub = Self.demoSubscription()
            KeychainStore.subscriptionURL = "demo"
            subscription = sub
            SharedStore.cachedSubscription = sub
            if selectedServerID == nil || !sub.servers.contains(where: { $0.id == selectedServerID }) {
                selectedServerID = sub.servers.first?.id
            }
        }
        #endif

        // Пробрасываем изменения VPN-статуса в состояние экрана — иначе SwiftUI
        // не наблюдает вложенный VPNManager и кнопка обновляется с задержкой.
        vpn.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var hasSubscription: Bool {
        KeychainStore.subscriptionURL != nil && subscription != nil
    }

    var servers: [Server] { subscription?.servers ?? [] }

    /// Спец-токен вкладки «Мои» в перетаскиваемой ленте.
    static let mineTabToken = "\u{1}__mine__"

    /// Группы-вкладки в пользовательском порядке.
    var orderedGroups: [String] {
        SharedStore.ordered(groups: subscription?.adminGroups ?? [])
    }

    /// Перетаскиваемые вкладки: группы + «Мои», в пользовательском порядке.
    var orderedTabs: [String] {
        SharedStore.ordered(groups: (subscription?.adminGroups ?? []) + [Self.mineTabToken])
    }

    /// Фиксирует новый порядок вкладок (после перетаскивания).
    func setTabOrder(_ order: [String]) { tabOrder = order }

    /// Специальный id режима «Авто» — ядро само держит самый быстрый сервер.
    static let autoID = "__auto__"

    var isAutoSelected: Bool { selectedServerID == Self.autoID }

    var selectedServer: Server? {
        guard let id = selectedServerID, id != Self.autoID else {
            // Для «Авто» показываем текущий фаворит по пингу
            return fastestServer ?? servers.first
        }
        return servers.first { $0.id == id } ?? servers.first
    }

    var fastestServer: Server? {
        servers.min { a, b in
            let pa = pings[a.id].flatMap { $0 >= 0 ? $0 : nil } ?? .max
            let pb = pings[b.id].flatMap { $0 >= 0 ? $0 : nil } ?? .max
            return pa < pb
        }
    }

    /// Сервер, к которому реально подключаемся (для флага в статусе/острове).
    var activeServer: Server? {
        isAutoSelected ? fastestServer : selectedServer
    }

    // MARK: - Подписка

    func activate(urlString: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        #if DEBUG
        // Демо-режим для разработки: ключ "demo" загружает тестовые серверы без сети
        if urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "demo" {
            let sub = Self.demoSubscription()
            KeychainStore.subscriptionURL = "demo"
            subscription = sub
            SharedStore.cachedSubscription = sub
            selectedServerID = sub.servers.first?.id
            return true
        }
        #endif
        do {
            let sub = try await SubscriptionClient().fetch(from: urlString)
            KeychainStore.subscriptionURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            subscription = sub
            SharedStore.cachedSubscription = sub
            if selectedServerID == nil {
                selectedServerID = sub.servers.first?.id
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshSubscription() async {
        guard let url = KeychainStore.subscriptionURL else { return }
        #if DEBUG
        if url == "demo" { return }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            let sub = try await SubscriptionClient().fetch(from: url)
            subscription = sub
            SharedStore.cachedSubscription = sub
            errorMessage = nil
        } catch {
            // Кэш остаётся рабочим — просто показываем, что обновить не вышло
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        if vpn.state != .disconnected { Task { await vpn.disconnect() } }
        KeychainStore.subscriptionURL = nil
        SharedStore.cachedSubscription = nil
        subscription = nil
        selectedServerID = nil
    }

    // MARK: - VPN

    func toggleConnection() async {
        #if DEBUG
        if Self.demoMode {
            if vpn.state == .connected || vpn.state == .connecting {
                vpn.stopDemo()
            } else {
                await vpn.startDemo()
            }
            return
        }
        #endif
        #if !canImport(Libbox)
        // Ядро не слинковано — реальный туннель не поднимется.
        vpn.setLastError(String(localized: "VPN core is missing. On Mac run: ./scripts/setup-ios.sh"))
        return
        #endif
        switch vpn.state {
        case .connected, .connecting:
            await vpn.disconnect()
        default:
            await startTunnel(reconnect: false)
        }
    }

    /// Запуск/перезапуск туннеля с текущим выбором (сервер или «Авто») и правилами.
    func startTunnel(reconnect: Bool) async {
        errorMessage = nil
        let auto = isAutoSelected
        let tunnelServers: [Server]
        if auto {
            tunnelServers = servers
        } else if let server = selectedServer {
            tunnelServers = [server]
        } else {
            errorMessage = String(localized: "Pick a server first")
            return
        }
        if reconnect {
            await vpn.reconnect(servers: tunnelServers, autoSelect: auto,
                                routingMode: routingMode, customRules: customRules,
                                killSwitch: killSwitchEnabled)
        } else {
            await vpn.connect(servers: tunnelServers, autoSelect: auto,
                              routingMode: routingMode, customRules: customRules,
                              killSwitch: killSwitchEnabled)
        }
    }

    /// Если туннель активен — применяет изменения переподключением.
    func reconnectIfConnected() async {
        guard vpn.state == .connected else { return }
        await startTunnel(reconnect: true)
    }

    /// Смена сервера: если подключены — переподключаемся к новому.
    func select(server: Server) async {
        let changed = selectedServerID != server.id
        selectedServerID = server.id
        if changed, vpn.state == .connected {
            await startTunnel(reconnect: true)
        }
    }

    /// Включение режима «Авто».
    func selectAuto() async {
        let changed = selectedServerID != Self.autoID
        selectedServerID = Self.autoID
        if changed, vpn.state == .connected {
            await startTunnel(reconnect: true)
        }
    }

    // MARK: - Пинг (как на Mac: фоновый прогон + пакетное применение результатов)

    @Published var pingingServerIDs: Set<String> = []
    private var pingTask: Task<Void, Never>?
    private var pendingPings: [String: Int] = [:]
    private var flushScheduled = false

    func pingAll() {
        guard !isPinging, !servers.isEmpty else { return }
        isPinging = true
        pingingServerIDs = Set(servers.map(\.id))
        let all = servers
        pingTask = Task.detached(priority: .utility) { [weak self] in
            await self?.runPingDetached(servers: all)
            await MainActor.run {
                self?.flushPings()
                self?.isPinging = false
                self?.pingingServerIDs = []
            }
        }
    }

    /// Пинг одного сервера (из контекстного меню).
    func pingOne(_ server: Server) {
        pingingServerIDs.insert(server.id)
        Task.detached(priority: .utility) { [weak self] in
            await self?.runPingDetached(servers: [server])
            await MainActor.run { self?.flushPings() }
        }
    }

    /// Прогон TCP-пинга вне главного потока; результаты складываются в буфер.
    nonisolated private func runPingDetached(servers: [Server]) async {
        await PingService.shared.ping(servers: servers) { [weak self] result in
            Task { @MainActor in self?.bufferPing(result) }
        }
    }

    /// Кладёт результат в буфер и планирует пакетное обновление UI (раз в ~150мс).
    private func bufferPing(_ result: PingResult) {
        guard pingingServerIDs.contains(result.serverID) else { return }
        pendingPings[result.serverID] = result.latencyMs ?? -1
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.flushPings()
        }
    }

    private func flushPings() {
        flushScheduled = false
        guard !pendingPings.isEmpty else { return }
        for (id, ms) in pendingPings {
            pings[id] = ms
            pingingServerIDs.remove(id)
        }
        pendingPings.removeAll()
    }

    /// Отмена пинга: незавершённые серверы остаются без значения.
    func cancelPing() {
        pingTask?.cancel()
        pingTask = nil
        pendingPings.removeAll()
        flushScheduled = false
        pingingServerIDs = []
        isPinging = false
    }

    // MARK: - Избранное и папки

    #if DEBUG
    private static func demoSubscription() -> ClevVPNKit.Subscription {
        // Реальная подписка (вкладки/серверы 1-в-1 как на Mac), секреты вычищены —
        // только для просмотра UI. Файл PreviewSubscription.json лежит в бандле.
        if let url = Bundle.main.url(forResource: "PreviewSubscription", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let sub = try? JSONDecoder().decode(ClevVPNKit.Subscription.self, from: data) {
            return sub
        }
        // Фолбэк на случай отсутствия ресурса — минимальная витрина.
        let links = """
        vless://11111111-1111-1111-1111-111111111111@10.0.0.1:443?type=tcp&security=reality&pbk=demo&fp=chrome&sni=yahoo.com&sid=01ab&flow=xtls-rprx-vision#Европа%20%7C%20%F0%9F%87%A9%F0%9F%87%AA%20%D0%A4%D1%80%D0%B0%D0%BD%D0%BA%D1%84%D1%83%D1%80%D1%82
        hysteria2://demo@10.0.0.3:8443?sni=hy.demo.com#Скорость%20%7C%20%F0%9F%87%AB%F0%9F%87%AE%20%D0%A5%D0%B5%D0%BB%D1%8C%D1%81%D0%B8%D0%BD%D0%BA%D0%B8
        """
        let servers = ShareLinkParser.parseSubscriptionContent(links)
        return ClevVPNKit.Subscription(
            servers: servers, title: "ClevVPN Demo",
            userInfo: SubscriptionUserInfo.parse("upload=1073741824; download=16106127360; total=107374182400; expire=1782000000"),
            announce: nil, supportURL: "https://t.me/clevvpn_support")
    }
    #endif

    func toggleFavorite(_ server: Server) {
        if favorites.contains(server.id) {
            favorites.remove(server.id)
        } else {
            favorites.insert(server.id)
        }
    }

    func addFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        folders.append(ServerFolder(name: trimmed))
    }

    func toggle(server: Server, in folder: ServerFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        if let position = folders[index].serverIDs.firstIndex(of: server.id) {
            folders[index].serverIDs.remove(at: position)
        } else {
            folders[index].serverIDs.append(server.id)
        }
    }
}
