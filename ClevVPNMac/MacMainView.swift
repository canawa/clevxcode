import SwiftUI
import ClevVPNKit

/// Главное окно Mac-версии: только подключение и серверы.
/// Настройки, приложения, правила и язык — в шестерёнке.
struct MacMainView: View {
    var body: some View {
        MacHomeView()
    }
}

/// Разделы, спрятанные под шестерёнкой.
struct MacSettingsSheet: View {
    @EnvironmentObject private var state: MacState
    @Environment(\.dismiss) private var dismiss

    @State private var tab: SettingsTab = .apps

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ClevSegmentedTabs(selection: $tab)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Divider().overlay(Theme.stroke)

            switch tab {
            case .apps: MacAppsView()
            case .rules: MacRulesView()
            case .subscription: MacSettingsView()
            case .language: MacLanguageView()
            }
        }
        .frame(width: 460, height: 560)
        .background(Theme.background)
        // Toast поверх листа настроек — иначе ошибка «терялась» внизу вкладки.
        .overlay(alignment: .top) {
            if let toast = state.toast {
                ToastView(toast: toast)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.toast)
    }
}

/// Выбор серверов для вкладки «Мои».
struct MacMineEditor: View {
    @EnvironmentObject private var state: MacState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Server] {
        guard !search.isEmpty else { return state.servers }
        return state.servers.filter { $0.rawName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("My servers")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            TextField("Search servers", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filtered) { server in
                        Button {
                            state.toggleFavorite(server)
                        } label: {
                            HStack(spacing: 10) {
                                Text(server.flagEmoji ?? "🌐")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(server.name)
                                        .font(.subheadline)
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                    if let desc = server.descriptionText, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption2)
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: state.favorites.contains(server.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(state.favorites.contains(server.id)
                                                     ? Theme.yellow : Theme.stroke)
                            }
                            .padding(10)
                            .card()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 440, height: 540)
        .background(Theme.background)
    }
}

/// Всплывающее уведомление сверху окна: зелёное (успех) / красное (проблема).
struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(toast.kind == .success ? Theme.green : Theme.red)
            Text(toast.text)
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surfaceLight, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                (toast.kind == .success ? Theme.green : Theme.red).opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }
}

/// Смена языка на macOS — применяется сразу, без перезапуска.
struct MacLanguageView: View {
    @AppStorage("appLanguage") private var appLanguage = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Language")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                VStack(spacing: 0) {
                    row("system", Text("System"))
                    Divider().overlay(Theme.stroke)
                    row("ru", Text(verbatim: "Русский"))
                    Divider().overlay(Theme.stroke)
                    row("en", Text(verbatim: "English"))
                }
                .card()
            }
            .padding(20)
        }
    }

    private func row(_ code: String, _ title: Text) -> some View {
        Button {
            guard appLanguage != code else { return }
            // Меняем и AppleLanguages (для bundle-строк), и appLanguage (для
            // environment locale) — иерархия пересобирается по .id(appLanguage).
            appLanguage = code
            if code == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            }
        } label: {
            HStack {
                title.foregroundColor(Theme.textPrimary)
                Spacer()
                if appLanguage == code {
                    Image(systemName: "checkmark").foregroundColor(Theme.yellow)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Главная

struct MacHomeView: View {
    @EnvironmentObject private var state: MacState

    @State private var filter: HomeFilter = .all
    @State private var showSettings = false

    var body: some View {
        mainStack
            .background(StatusGlow(status: glowStatus).ignoresSafeArea())
            .overlay(alignment: .top) {
                if let toast = state.toast {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.toast)
    }

    private var glowStatus: StatusGlow.Status {
        switch state.tunnel.state {
        case .connected: return .on
        case .connecting, .disconnecting: return .busy
        case .disconnected: return .off
        }
    }

    private var mainStack: some View {
        VStack(spacing: 12) {
            topBar

            ConnectButton(state: buttonState, size: 150, connectedAt: state.tunnel.connectedAt, isPinging: state.isPinging) {
                // Пока идёт пинг (и VPN выключен) — нажатие отменяет пинг
                if state.isPinging && state.tunnel.state == .disconnected {
                    state.cancelPing()
                } else {
                    Task { await state.toggleConnection() }
                }
            }
            .padding(.top, 2)

            // Уведомления / ошибки — под кнопкой Start (не внизу настроек).
            statusNotice

            setupBanner

            // Announce + трафик/дата — одна карточка, разделённые линией
            VStack(spacing: 0) {
                if let announce = state.subscription?.announce,
                   !announce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AnnounceText(text: announce)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    Divider().overlay(Theme.stroke)
                }
                infoBar
            }
            .card()
            .padding(.horizontal, 20)

            HomeFilterChips(filter: $filter,
                            order: state.filterOrder,
                            onReorder: { state.filterOrder = $0 })

            ScrollView {
                LazyVStack(spacing: 6) {
                    if filteredServers.isEmpty {
                        Text("No servers here yet")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.top, 24)
                    }
                    ForEach(filteredServers) { server in
                        QuickServerRow(
                            server: server,
                            isSelected: state.selectedServer?.id == server.id,
                            isFavorite: state.favorites.contains(server.id),
                            ping: state.pings[server.id],
                            isPinging: state.pingingServerIDs.contains(server.id)
                        ) {
                            Task { await state.select(server: server) }
                        }
                        .contextMenu {
                            Button {
                                state.pingOne(server)
                            } label: {
                                Label("Ping this server", systemImage: "bolt.horizontal")
                            }
                            Button {
                                state.toggleFavorite(server)
                            } label: {
                                if state.favorites.contains(server.id) {
                                    Label("Remove from My", systemImage: "star.slash")
                                } else {
                                    Label("Add to My", systemImage: "star")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .task {
            state.checkConflict()
            state.startAutoRefresh()   // свежая подписка + автообновление по интервалу
            if state.pings.isEmpty {
                state.pingAll()
            }
        }
        // Перепроверяем конфликт при возврате в приложение и каждые 5 секунд
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            state.checkConflict()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            state.checkConflict()
        }
        .sheet(isPresented: $showSettings) {
            MacSettingsSheet().environmentObject(state)
        }
    }

    /// Строка трафика и даты с иконками пинга (слева) и обновления (справа).
    private var infoBar: some View {
        HStack(spacing: 10) {
            Button {
                state.pingAll()
            } label: {
                if state.isPinging {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundColor(Theme.yellow)
                }
            }
            .buttonStyle(.plain)
            .help(Text("Ping servers"))
            .disabled(state.isPinging)

            if let info = state.subscription?.userInfo {
                if let used = info.usedBytes {
                    Label {
                        if let total = info.totalBytes, total > 0 {
                            Text(verbatim: "\(format(used)) / \(format(total))")
                        } else {
                            Text(verbatim: format(used))
                        }
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                if let expires = info.expiresAt {
                    Label {
                        Text(expires, style: .date)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                }
            } else {
                Spacer()
            }

            Button {
                Task { await state.refreshSubscription() }
            } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(Theme.yellow)
                }
            }
            .buttonStyle(.plain)
            .help(Text("Update subscription"))
            .disabled(state.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    /// Верхняя панель: логотип по центру (как на телефоне), шестерёнка в углу.
    private var topBar: some View {
        ZStack {
            ClevLogoFull(logoHeight: 20)
            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(Text("Settings"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// Красный текст под Start: ошибка туннеля, подписки или конфликт VPN.
    @ViewBuilder
    private var statusNotice: some View {
        if let error = state.tunnel.lastError ?? state.errorMessage {
            Text(error)
                .font(.caption2)
                .foregroundColor(Theme.red)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .textSelection(.enabled)
        } else if let conflict = state.conflict {
            Text("You already have another VPN turned on. Turn it off and try again.")
                .font(.caption2)
                .foregroundColor(Theme.red)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .onTapGesture { state.recheckConflict() }
                .help(Text(verbatim: conflict.name))
        }
    }

    /// Баннер первичной настройки: нет ядра или нет прав.
    @ViewBuilder
    private var setupBanner: some View {
        if state.tunnel.corePath == nil {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.orange)
                Text("Install the core: brew install sing-box")
                    .font(.caption)
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
                Spacer()
                Button("Re-check") { state.tunnel.refreshEnvironment() }
                    .font(.caption)
            }
            .padding(10)
            .card()
            .padding(.horizontal, 20)
        } else if !state.tunnel.isAuthorized {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(Theme.yellow)
                Text("Allow ClevVPN to manage the tunnel (admin password, one time)")
                    .font(.caption)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("Allow") {
                    Task { await state.tunnel.authorize() }
                }
                .font(.caption.weight(.semibold))
            }
            .padding(10)
            .card()
            .padding(.horizontal, 20)
        }
    }

    /// Серверы выбранной вкладки; избранные закрепляются сверху.
    private var filteredServers: [Server] {
        filter.apply(to: state.servers).sorted { a, b in
            let aFav = state.favorites.contains(a.id)
            let bFav = state.favorites.contains(b.id)
            return aFav && !bFav
        }
    }

    private var buttonState: ConnectButton.Status {
        switch state.tunnel.state {
        case .connected: return .on
        case .connecting, .disconnecting: return .busy
        case .disconnected: return .off
        }
    }
}
