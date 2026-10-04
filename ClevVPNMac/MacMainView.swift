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

    enum Tab: String, CaseIterable {
        case apps, rules, subscription, language
    }

    @State private var tab: Tab = .apps

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

            Picker("", selection: $tab) {
                Text("Apps").tag(Tab.apps)
                Text("Rules").tag(Tab.rules)
                Text("Subscription").tag(Tab.subscription)
                Text("Language").tag(Tab.language)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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

    private enum QuickFilter: Hashable {
        case all
        case group(String)
    }

    @State private var filter: QuickFilter = .all
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

            // Только ошибка (текст статуса убран — состояние видно по кнопке)
            if let error = state.tunnel.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(Theme.red)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .textSelection(.enabled)
            }

            conflictBanner

            setupBanner

            // Announce + трафик/дата — одна карточка, разделённые линией
            VStack(spacing: 0) {
                if let announce = state.subscription?.announce,
                   !announce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(announce)
                        .font(.subheadline)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    Divider().overlay(Theme.stroke)
                }
                infoBar
            }
            .card()
            .padding(.horizontal, 20)

            filterChips

            ScrollView {
                LazyVStack(spacing: 8) {
                    if filter == .all {
                        AutoServerRow(
                            isSelected: state.isAutoSelected,
                            fastest: state.fastestServer,
                            ping: state.fastestServer.flatMap { state.pings[$0.id] }
                        ) {
                            Task { await state.selectAuto() }
                        }
                    }
                    ForEach(filteredServers) { server in
                        QuickServerRow(
                            server: server,
                            isSelected: !state.isAutoSelected && state.selectedServer?.id == server.id,
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

    /// Баннер конфликта: обнаружен другой активный VPN-клиент.
    @ViewBuilder
    private var conflictBanner: some View {
        if let conflict = state.conflict {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundColor(Theme.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Another VPN is running: \(conflict.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Turn it off before connecting — two VPNs conflict over routing")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Button("Re-check") { state.recheckConflict() }
                    .font(.caption)
            }
            .padding(10)
            .background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Theme.red.opacity(0.5), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }

    /// Баннер первичной настройки: нет ядра или нет прав.
    @ViewBuilder
    private var setupBanner: some View {
        if state.tunnel.corePath == nil {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.orange)
                Text("VPN core is missing from the app package")
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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, label: Text("All"))
                ReorderableTabStrip(
                    groups: state.orderedGroups,
                    isSelected: { filter == .group($0) },
                    onTap: { filter = .group($0) },
                    onReorder: { state.setTabOrder($0) }
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 5)
        }
    }

    private func chip(_ value: QuickFilter, label: Text) -> some View {
        Button {
            filter = value
        } label: {
            label
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    filter == value ? AnyShapeStyle(Theme.yellowGradient) : AnyShapeStyle(Theme.surface),
                    in: Capsule()
                )
                .foregroundColor(filter == value ? .black : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var filteredServers: [Server] {
        var servers = state.servers
        switch filter {
        case .all: break
        case .group(let group): servers = servers.filter { $0.group == group }
        }
        // Избранные закрепляются сверху
        return servers.sorted { a, b in
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
