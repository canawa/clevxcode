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
                // Смена языка без перезапуска — переопределяем locale налету
                .environment(\.locale, appLanguage == "system" ? .current : Locale(identifier: appLanguage))
                .id(appLanguage)   // пересобрать иерархию при смене языка
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
    }
}

/// Компактная панель в строке меню: кнопка вкл/выкл и последние серверы.
/// Стиль .window — окно не закрывается при выборе сервера, можно тут же нажать «Вкл».
struct MenuBarPanel: View {
    @EnvironmentObject private var state: MacState

    enum MenuTab: Equatable { case all, group(String) }
    @State private var tab: MenuTab = .all

    private var isConnected: Bool { state.tunnel.state == .connected }
    private var isBusy: Bool { state.tunnel.state == .connecting || state.tunnel.state == .disconnecting }

    /// Вкладки-чипы: Все + группы (перетаскиваемые).
    @ViewBuilder private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tabChip(.all, Text("All"))
                ReorderableTabStrip(
                    groups: state.orderedGroups,
                    isSelected: { tab == .group($0) },
                    compact: true,
                    onTap: { tab = .group($0) },
                    onReorder: { state.setTabOrder($0) }
                )
            }
            .padding(.vertical, 5)   // место для увеличенной вкладки при перетаскивании
        }
    }

    private func tabChip(_ value: MenuTab, _ label: Text) -> some View {
        Button { tab = value } label: {
            label
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(tab == value ? AnyShapeStyle(Theme.yellow) : AnyShapeStyle(Theme.surface),
                            in: Capsule())
                .foregroundColor(tab == value ? .black : .secondary)
        }
        .buttonStyle(.plain)
    }

    /// Серверы для показа по выбранной вкладке.
    private var menuServers: [Server] {
        switch tab {
        case .group(let g):
            return state.servers.filter { $0.group == g }
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

                Divider()

                // Вкладки серверов (Все + группы из админки)
                tabs

                // Авто + прокручиваемый список серверов
                menuRow(title: Text("Auto — fastest server"), flag: "⚡",
                        selected: state.isAutoSelected) {
                    Task { await state.selectAuto() }
                }

                if !menuServers.isEmpty {
                    Text(sectionTitle)
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(menuServers) { server in
                                menuRow(title: Text(verbatim: server.name), flag: server.flagEmoji ?? "🌐",
                                        selected: !state.isAutoSelected && state.selectedServerID == server.id) {
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
                state.tunnel.stop()
                NSApplication.shared.terminate(nil)
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
