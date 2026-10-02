import SwiftUI
import ClevVPNKit

/// Главный экран: кнопка подключения и быстрый выбор сервера — всё на одной странице.
struct ConnectView: View {
    @EnvironmentObject private var state: AppState

    private enum QuickFilter: Hashable {
        case all
        case auto
        case group(String)
    }

    @State private var filter: QuickFilter = .all

    private var glowStatus: StatusGlow.Status {
        switch state.vpn.state {
        case .connected: return .on
        case .connecting, .disconnecting: return .busy
        default: return .off
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                StatusGlow(status: glowStatus).ignoresSafeArea()

                VStack(spacing: 12) {
                    ClevLogoFull(logoHeight: 22)
                        .padding(.top, 4)

                    ConnectButton(state: buttonState, size: 196, connectedAt: state.vpn.connectedAt, isPinging: state.isPinging) {
                        if state.isPinging && state.vpn.state == .disconnected {
                            state.cancelPing()
                        } else {
                            Task { await state.toggleConnection() }
                        }
                    }
                    .padding(.top, 6)

                    // Состояние видно по самой кнопке; ошибки — под Start
                    // (туннель + обновление подписки), как на Mac.
                    if !AppState.demoMode {
                        if let error = state.vpn.lastError ?? state.errorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(Theme.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }

                    // Announce + трафик/дата — одна карточка, разделённые линией (как на Mac)
                    VStack(spacing: 0) {
                        if let announce = state.subscription?.announce,
                           !announce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(announce)
                                .font(.subheadline)
                                .foregroundColor(Theme.textPrimary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            Divider().overlay(Theme.stroke)
                        }
                        infoBar
                    }
                    .card()
                    .padding(.horizontal, 20)

                    filterChips

                    quickServerList
                }
            }
            .task {
                // Автопинг при первом открытии, чтобы список сразу был информативным
                if state.pings.isEmpty {
                    state.pingAll()
                }
                #if DEBUG
                // Для проверки анимации подключения из скриптов
                if ProcessInfo.processInfo.environment["CLEV_AUTOCONNECT"] == "1",
                   state.vpn.state == .disconnected {
                    await state.toggleConnection()
                }
                #endif
            }
        }
    }

    // MARK: - Трафик/дата с кнопками пинга и обновления (как на Mac)

    private var infoBar: some View {
        HStack(spacing: 10) {
            Button {
                if state.isPinging { state.cancelPing() } else { state.pingAll() }
            } label: {
                if state.isPinging {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundColor(Theme.yellow)
                }
            }
            .buttonStyle(.plain)

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
                Task { await state.refreshSubscription(); state.pingAll() }
            } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(Theme.yellow)
                }
            }
            .buttonStyle(.plain)
            .disabled(state.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    // MARK: - Фильтры

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, label: Text("All"))
                chip(.auto, label: Text("⚡ Auto"))
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
                .padding(.vertical, 7)
                .background(
                    filter == value ? AnyShapeStyle(Theme.yellowGradient) : AnyShapeStyle(Theme.surface),
                    in: Capsule()
                )
                .foregroundColor(filter == value ? .black : Theme.textSecondary)
        }
    }

    // MARK: - Быстрый список серверов

    private var filteredServers: [Server] {
        var servers = state.servers
        switch filter {
        case .all:
            break
        case .auto:
            return []
        case .group(let group):
            servers = servers.filter { $0.group == group }
        }
        // Избранные закрепляются сверху, дальше — порядок из подписки
        return servers.sorted { a, b in
            let aFav = state.favorites.contains(a.id)
            let bFav = state.favorites.contains(b.id)
            return aFav && !bFav
        }
    }

    private var quickServerList: some View {
        List {
            if filter == .auto || filter == .all {
                AutoServerRow(
                    isSelected: state.isAutoSelected,
                    fastest: state.fastestServer,
                    ping: state.fastestServer.flatMap { state.pings[$0.id] }
                ) {
                    Task { await state.selectAuto() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                // Свайп вправо — приоткрывает кнопку пинга; полный свайп пингует
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        state.pingOne(server)
                    } label: {
                        Label("Ping", systemImage: "bolt.horizontal.fill")
                    }
                    .tint(Theme.yellow)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable {
            await state.refreshSubscription()
            state.pingAll()
        }
    }

    private var buttonState: ConnectButton.Status {
        switch state.vpn.state {
        case .connected: return .on
        case .connecting, .disconnecting: return .busy
        default: return .off
        }
    }
}

/// Выбор серверов для вкладки «Мои».
struct MineEditorSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.servers) { server in
                            Button {
                                state.toggleFavorite(server)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(server.flagEmoji ?? "🌐")
                                    Text(server.name)
                                        .font(.subheadline)
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    Image(systemName: state.favorites.contains(server.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(state.favorites.contains(server.id)
                                                         ? Theme.yellow : Theme.stroke)
                                }
                                .padding(12)
                                .card()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(Text("My servers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
