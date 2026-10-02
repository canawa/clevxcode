import SwiftUI
import ClevVPNKit

@main
struct ClevVPNApp: App {
    @StateObject private var state = AppState()
    @AppStorage("appLanguage") private var appLanguage = "system"

    init() {
        #if canImport(Libbox)
        LibboxPingEngine.install()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(Theme.yellow)
                // Смена языка без перезапуска — переопределяем locale налету
                .environment(\.locale, appLanguage == "system" ? .current : Locale(identifier: appLanguage))
                .id(appLanguage)   // пересобрать иерархию при смене языка
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if state.hasSubscription {
                MainTabView()
            } else {
                ActivationView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.hasSubscription)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab: Int = {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["CLEV_SCREEN"] {
        case "servers": return 1
        case "routing": return 2
        case "settings": return 3
        default: return 0
        }
        #else
        return 0
        #endif
    }()

    var body: some View {
        TabView(selection: $tab) {
            ConnectView()
                .tabItem { Label("Home", systemImage: "power.circle.fill") }
                .tag(0)
            ServersView()
                .tabItem { Label("Servers", systemImage: "globe") }
                .tag(1)
            RoutingView()
                .tabItem { Label("Routing", systemImage: "arrow.triangle.branch") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .task {
            await state.vpn.refresh()
            await state.refreshSubscription()
        }
    }
}
