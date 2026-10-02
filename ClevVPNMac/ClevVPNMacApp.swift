import SwiftUI
import ClevVPNKit

@main
struct ClevVPNMacApp: App {
    @StateObject private var state = MacState()
    @AppStorage("appLanguage") private var appLanguage = "system"

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(Theme.yellow)
                // Смена языка без перезапуска: SwiftUI сам разрешает строки по
                // locale из окружения, поэтому пересобирать иерархию (.id) не
                // нужно — переключение мгновенное.
                .environment(\.locale, appLanguage == "system" ? .current : Locale(identifier: appLanguage))
                // Узкий вертикальный формат как у Happ (ширина < высота)
                .frame(width: 420, height: 780)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 780)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(state)
        } label: {
            // Монохромная (нативная) когда выключено, жёлтая когда подключено —
            // цвет иконки заодно показывает статус VPN.
            Image("MenuBarIcon")
                .renderingMode(state.tunnel.state == .connected ? .original : .template)
        }
        .menuBarExtraStyle(.window)   // окно не закрывается при выборе сервера
    }
}

struct MacRootView: View {
    @EnvironmentObject private var state: MacState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if state.hasSubscription {
                MacMainView()
            } else {
                MacActivationView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.hasSubscription)
        .overlay(alignment: .top) {
            if let toast = state.toast {
                ToastView(toast: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.toast)
    }
}

/// Компактная панель в строке меню: кнопка вкл/выкл и последние серверы.
/// Стиль .window — окно не закрывается при выборе сервера, можно тут же нажать «Вкл».
struct MenuBarPanel: View {
    @EnvironmentObject private var state: MacState

    @State private var tab: HomeFilter = .all

    private var isConnected: Bool { state.tunnel.state == .connected }
    private var isBusy: Bool { state.tunnel.state == .connecting || state.tunnel.state == .disconnecting }

    /// Серверы для показа по выбранной вкладке.
    private var menuServers: [Server] {
        switch tab {
        case .category:
            return tab.apply(to: state.servers)
        case .all:
            // Последние использованные сверху, затем весь остальной список —
            // список всегда полный и прокручиваемый.
            let recents = state.recentServers.filter { $0.id != state.selectedServerID }
            let recentIDs = Set(recents.map(\.id))
            let rest = state.servers.filter { !recentIDs.contains($0.id) }
            return recents + rest
        }
    }

    private var sectionTitle: LocalizedStringKey {
        guard tab == .all else { return "Servers" }
        return state.recentServers.contains { $0.id != state.selectedServerID } ? "Recent" : "Servers"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                ClevLogoFull(logoHeight: 16)
                Spacer()
                Circle()
                    .fill(isConnected ? Theme.green : Theme.textSecondary.opacity(0.5))
                    .frame(width: 8, height: 8)
            }

            if state.hasSubscription {
                // Кнопка подключения
                Button {
                    Task { await state.toggleConnection() }
                } label: {
                    HStack {
                        if isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "power")
                        }
                        Text(isConnected ? "Disconnect" : "Connect")
                            .fontWeight(.semibold)
                        Spacer()
                        if let s = state.selectedServer {
                            Text(verbatim: "\(s.flagEmoji ?? "") \(s.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(isConnected ? Theme.green.opacity(0.18) : Theme.yellow.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let notice = state.statusNoticeText {
                    Text(notice)
                        .font(.caption2)
                        .foregroundColor(Theme.red)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                // Вкладки серверов: Все + фиксированные категории (как на Home)
                HomeFilterChips(filter: $tab,
                                order: state.filterOrder,
                                onReorder: { state.filterOrder = $0 },
                                compact: true,
                                horizontalPadding: 0)

                if !menuServers.isEmpty {
                    Text(sectionTitle)
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(menuServers) { server in
                                menuRow(title: Text(verbatim: server.name), flag: server.flagEmoji ?? "🌐",
                                        selected: state.selectedServerID == server.id) {
                                    Task { await state.select(server: server) }
                                }
                            }
                        }
                    }
                    // Фикс высоты по контенту — иначе ScrollView в .window схлопывается в 0
                    .frame(height: min(CGFloat(menuServers.count) * 30 + 4, 220))
                }

                Divider()
            }

            Button("Quit ClevVPN") {
                state.quit()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func menuRow(title: Text, flag: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(verbatim: flag)
                title.lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.caption).foregroundColor(Theme.yellow)
                }
            }
            .padding(.vertical, 5).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
