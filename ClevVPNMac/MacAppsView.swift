import SwiftUI
import AppKit
import ClevVPNKit

/// Маршрутизация по приложениям — фишка macOS-версии.
struct MacAppsView: View {
    @EnvironmentObject private var state: MacState
    @State private var installedApps: [InstalledApp] = MacAppsView.cachedApps ?? []
    @State private var search = ""

    struct InstalledApp: Identifiable, @unchecked Sendable {
        let name: String
        let path: String
        let icon: NSImage
        var id: String { path }
    }

    /// Список установленных приложений на время работы программы: при повторном
    /// входе на вкладку он не перечитывается с диска — иначе вкладка подвисала
    /// и перестраивалась при каждом открытии.
    @MainActor private static var cachedApps: [InstalledApp]?

    var body: some View {
        VStack(spacing: 12) {
            modePicker
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if state.appRoutingMode != .off {
                TextField("Search apps", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredApps) { app in
                            appRow(app)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.stroke)
                    Text("Choose a mode to route traffic by app")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
        }
        .task { await loadApps() }
        .onChange(of: state.appRoutingMode) { _ in
            Task { await state.reconnectIfConnected() }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App routing")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            // Свой сегментный переключатель вместо системного: тот на длинных
            // русских подписях был шире окна, и блок обрезался с обеих сторон.
            // Подписи короткие — влезают в одну строку; полный смысл в подсказке ниже.
            ClevSegmentedPicker(selection: $state.appRoutingMode, options: [
                (.off, "Off"),
                (.bypassSelected, "Bypass VPN"),
                (.onlySelected, "Only via VPN")
            ])

            Text(modeHint)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var modeHint: LocalizedStringKey {
        switch state.appRoutingMode {
        case .off:
            return "All traffic follows the mode from the «Rules» tab"
        case .bypassSelected:
            return "Selected apps go direct; everything else — via VPN"
        case .onlySelected:
            return "Only selected apps use VPN; everything else goes direct"
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let isOn = state.appRules.contains { $0.bundlePath == app.path }
        return Button {
            if isOn {
                state.appRules.removeAll { $0.bundlePath == app.path }
            } else {
                state.appRules.append(AppRule(name: app.name, bundlePath: app.path))
            }
            Task { await state.reconnectIfConnected() }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                Text(app.name)
                    .font(.subheadline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isOn ? Theme.yellow : Theme.stroke)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return installedApps }
        return installedApps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// Первый вход — сканируем диск в фоне (главный поток не блокируется),
    /// дальше берём из кэша.
    private func loadApps() async {
        let apps: [InstalledApp]
        if let cached = Self.cachedApps {
            apps = cached
        } else {
            apps = await Task.detached(priority: .userInitiated) {
                MacAppsView.scanApplications()
            }.value
            Self.cachedApps = apps
        }
        installedApps = merged(apps)
    }

    /// Выбранные, но уже удалённые приложения тоже показываем.
    private func merged(_ apps: [InstalledApp]) -> [InstalledApp] {
        var result = apps
        for rule in state.appRules where !result.contains(where: { $0.path == rule.bundlePath }) {
            result.append(InstalledApp(name: rule.name, bundlePath: rule.bundlePath))
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    nonisolated private static func scanApplications() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications"]
        for dir in dirs {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for item in items where item.hasSuffix(".app") {
                let path = dir + "/" + item
                let name = FileManager.default.displayName(atPath: path)
                    .replacingOccurrences(of: ".app", with: "")
                apps.append(InstalledApp(name: name, bundlePath: path))
            }
        }
        return apps
    }
}

private extension MacAppsView.InstalledApp {
    init(name: String, bundlePath: String) {
        // Иконку сразу берём маленькой — рисовать 32pt дешевле, чем полноразмерную
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        icon.size = NSSize(width: 32, height: 32)
        self.init(name: name, path: bundlePath, icon: icon)
    }
}
