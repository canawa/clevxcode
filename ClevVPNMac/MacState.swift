import Foundation
import SwiftUI
import Combine
import ClevVPNKit

/// Всплывающее уведомление сверху окна.
struct ToastMessage: Equatable, Identifiable {
    enum Kind { case success, error }
    let id = UUID()
    let kind: Kind
    let text: String
}

/// Состояние Mac-приложения: подписка, серверы, выбор, правила.
@MainActor
final class MacState: ObservableObject {
    @Published var subscription: ClevVPNKit.Subscription?
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var selectedServerID: String? {
        didSet { SharedStore.selectedServerID = selectedServerID }
    }
    @Published var favorites: Set<String> {
        didSet { SharedStore.favoriteServerIDs = favorites }
    }
    /// Последние использованные серверы (id, свежие первыми).
    @Published var recentServerIDs: [String] {
        didSet { SharedStore.recentServerIDs = recentServerIDs }
    }
    /// Пользовательский порядок вкладок-групп.
    @Published var tabOrder: [String] {
        didSet { SharedStore.tabOrder = tabOrder }
    }
    @Published var routingMode: RoutingMode {
        didSet { SharedStore.routingMode = routingMode }
    }
    @Published var customRules: [RoutingRule] {
        didSet { SharedStore.customRules = customRules }
    }
    @Published var appRules: [AppRule] {
        didSet { SharedStore.appRules = appRules }
    }
    @Published var appRoutingMode: AppRoutingMode {
        didSet { SharedStore.appRoutingMode = appRoutingMode }
    }
    @Published var killSwitchEnabled: Bool {
        didSet {
            guard killSwitchEnabled != oldValue else { return }
            SharedStore.killSwitchEnabled = killSwitchEnabled
            if killSwitchEnabled {
                // Включили при уже активном туннеле — сразу поставить блокировку
                if tunnel.state == .connected {
                    let hosts = currentTunnelHosts
                    Task { await activateKillSwitch(hosts: hosts) }
                }
            } else {
                // Выключили — снять блокировку
                Task.detached { KillSwitch.disable() }
            }
        }
    }
    /// Показывать флаг подключённой страны в меню-баре.
    @Published var statusFlagEnabled: Bool {
        didSet { SharedStore.statusFlagEnabled = statusFlagEnabled }
    }
    @Published var pings: [String: Int]
    @Published var isPinging = false
    /// Серверы, для которых пинг сейчас выполняется (для анимации-спиннера).
    @Published var pingingServerIDs: Set<String> = []
    /// Обнаруженный другой VPN-клиент (Happ, v2ray…), если есть.
    @Published var conflict: ConflictDetector.Conflict?
    /// Всплывающее уведомление сверху.
    @Published var toast: ToastMessage?

    let tunnel = MacTunnel()
    private var toastDismissTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    static let autoID = "__auto__"

    init() {
        subscription = SharedStore.cachedSubscription
        selectedServerID = SharedStore.selectedServerID
        favorites = SharedStore.favoriteServerIDs
        recentServerIDs = SharedStore.recentServerIDs
        tabOrder = SharedStore.tabOrder
        routingMode = SharedStore.routingMode
        customRules = SharedStore.customRules
        appRules = SharedStore.appRules
        appRoutingMode = SharedStore.appRoutingMode
        killSwitchEnabled = SharedStore.killSwitchEnabled
        statusFlagEnabled = SharedStore.statusFlagEnabled
        pings = SharedStore.pingResults
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLEV_DEMO"] == "1" {
            KeychainStore.subscriptionURL = "demo"
            SharedStore.cachedSubscription = nil
            subscription = nil
        }
        #endif

        // Пробрасываем изменения туннеля (state, lastError и т.п.) в состояние
        // экрана — иначе SwiftUI не наблюдает вложенный ObservableObject и кнопка
        // обновляется с задержкой (по следующему тику другого @Published).
        tunnel.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var hasSubscription: Bool {
        KeychainStore.subscriptionURL != nil && subscription != nil
    }

    var servers: [Server] { subscription?.servers ?? [] }

    var isAutoSelected: Bool { selectedServerID == Self.autoID }

    var selectedServer: Server? {
        guard let id = selectedServerID, id != Self.autoID else {
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
        isLoading = true
        defer { isLoading = false }
        do {
            let sub = try await SubscriptionClient().fetch(from: url)
            subscription = sub
            SharedStore.cachedSubscription = sub
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Тихое обновление подписки (без индикатора загрузки) — для автообновления.
    private func silentRefresh() async {
        guard let url = KeychainStore.subscriptionURL else { return }
        if let sub = try? await SubscriptionClient().fetch(from: url) {
            subscription = sub
            SharedStore.cachedSubscription = sub
        }
    }

    /// Запускает автообновление: сразу при старте + по интервалу из Remnawave
    /// (profile-update-interval, часы; по умолчанию 1 час).
    func startAutoRefresh() {
        guard KeychainStore.subscriptionURL != nil else { return }
        Task {
            await silentRefresh()   // подтянуть свежие данные (в т.ч. описания серверов)
            while !Task.isCancelled {
                let hours = max(1, subscription?.updateIntervalHours ?? 1)
                try? await Task.sleep(nanoseconds: UInt64(hours) * 3_600 * 1_000_000_000)
                if Task.isCancelled { break }
                await silentRefresh()
            }
        }
    }

    func logout() {
        if tunnel.state != .disconnected { tunnel.stop() }
        Task.detached { KillSwitch.disable() }
        KeychainStore.subscriptionURL = nil
        SharedStore.cachedSubscription = nil
        subscription = nil
        selectedServerID = nil
    }

    // MARK: - Туннель

    func toggleConnection() async {
        switch tunnel.state {
        case .connected, .connecting:
            tunnel.stop()
            // Штатное отключение — снимаем блокировку Kill Switch
            Task.detached { KillSwitch.disable() }
        default:
            await startTunnel()
        }
    }

    /// Хосты серверов, которые сейчас в конфиге туннеля (для правил Kill Switch).
    private var currentTunnelHosts: [String] {
        if isAutoSelected { return servers.map(\.host) }
        if let server = selectedServer { return [server.host] }
        return []
    }

    func startTunnel() async {
        let auto = isAutoSelected
        let tunnelServers: [Server]
        if auto {
            tunnelServers = servers
        } else if let server = selectedServer {
            tunnelServers = [server]
        } else {
            return
        }
        // Kill Switch требует прав pfctl — спрашиваем их до подъёма туннеля,
        // чтобы разовый запрос пароля не выскочил уже после подключения.
        if killSwitchEnabled { await tunnel.ensurePfctlAuthorized() }
        await tunnel.start(servers: tunnelServers, autoSelect: auto,
                           routingMode: routingMode, customRules: customRules,
                           appRules: appRules, appRoutingMode: appRoutingMode)
        // После успешного подъёма туннеля — включаем Kill Switch, если он в настройках.
        // Правила pf переживут падение ядра → интернет заблокируется без утечки IP.
        if killSwitchEnabled, tunnel.state == .connected {
            let hosts = tunnelServers.map(\.host)
            Task.detached { KillSwitch.enable(serverHosts: hosts) }
        }
    }

    /// Ставит блокировку Kill Switch, предварительно убедившись в правах pfctl.
    private func activateKillSwitch(hosts: [String]) async {
        guard await tunnel.ensurePfctlAuthorized() else { return }
        Task.detached { KillSwitch.enable(serverHosts: hosts) }
    }

    /// Применяет изменения перезапуском туннеля, если он активен.
    func reconnectIfConnected() async {
        guard tunnel.state == .connected else { return }
        tunnel.stop()
        // Короткая пауза, чтобы старое ядро сняло маршруты перед новым
        try? await Task.sleep(nanoseconds: 300_000_000)
        await startTunnel()
    }

    func select(server: Server) async {
        let changed = selectedServerID != server.id
        selectedServerID = server.id
        noteRecent(server.id)
        if changed { await reconnectIfConnected() }
    }

    /// Двигает сервер в начало списка последних использованных (макс 8).
    private func noteRecent(_ id: String) {
        var list = recentServerIDs
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        recentServerIDs = Array(list.prefix(8))
    }

    /// Последние использованные серверы, существующие в текущей подписке.
    var recentServers: [Server] {
        recentServerIDs.compactMap { id in servers.first { $0.id == id } }
    }

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

    func selectAuto() async {
        let changed = selectedServerID != Self.autoID
        selectedServerID = Self.autoID
        if changed { await reconnectIfConnected() }
    }

    func toggleFavorite(_ server: Server) {
        if favorites.contains(server.id) {
            favorites.remove(server.id)
        } else {
            favorites.insert(server.id)
        }
    }

    // MARK: - Конфликт с другим VPN

    /// Проверяет, запущен ли другой VPN-клиент. Запуск route/ps выносим в фон,
    /// чтобы не подвешивать интерфейс (иначе кнопка «думает»).
    func checkConflict() {
        let active = tunnel.state == .connected || tunnel.state == .connecting
        Task.detached(priority: .utility) {
            let result = ConflictDetector.detect(ownTunnelActive: active)
            await MainActor.run { self.conflict = result }
        }
    }

    /// Ручная перепроверка по кнопке — с всплывающим уведомлением о результате.
    func recheckConflict() {
        let active = tunnel.state == .connected || tunnel.state == .connecting
        Task.detached(priority: .userInitiated) {
            let result = ConflictDetector.detect(ownTunnelActive: active)
            await MainActor.run {
                self.conflict = result
                self.showConflictToast()
            }
        }
    }

    private func showConflictToast() {
        if let conflict {
            showToast(.error, text: String(
                format: String(localized: "Another VPN is still on: %@", bundle: .main),
                conflict.name))
        } else {
            showToast(.success, text: String(localized: "No other VPN — all clear", bundle: .main))
        }
    }

    func showToast(_ kind: ToastMessage.Kind, text: String) {
        toastDismissTask?.cancel()
        toast = ToastMessage(kind: kind, text: text)
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toast = nil }
        }
    }

    // MARK: - Пинг

    private var pingTask: Task<Void, Never>?
    private var pendingPings: [String: Int] = [:]
    private var flushScheduled = false

    /// Пинг всех серверов. Выполняется в отсоединённом фоне (не грузит главный
    /// поток), результаты применяются к UI пачками — интерфейс остаётся
    /// отзывчивым, вкладки свободно переключаются во время пинга.
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

    /// Отмена пинга: незавершённые серверы просто остаются без значения
    /// (спиннер убирается, чёрточка не ставится).
    func cancelPing() {
        pingTask?.cancel()
        pingTask = nil
        pendingPings.removeAll()
        flushScheduled = false
        pingingServerIDs = []
        isPinging = false
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

    /// Кладёт результат в буфер и планирует пакетное обновление UI (раз в ~150мс),
    /// чтобы не перерисовывать список на каждый из десятков результатов.
    private func bufferPing(_ result: PingResult) {
        // Результат применяем только если сервер всё ещё «проверяется» —
        // после отмены pingingServerIDs пуст, поздние результаты игнорируются.
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
}
