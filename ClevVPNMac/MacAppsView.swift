import SwiftUI
import AppKit
import ClevVPNKit

/// Маршрутизация по приложениям — фишка macOS-версии.
struct MacAppsView: View {
    @EnvironmentObject private var state: MacState
    @State private var installedApps: [InstalledApp] = []
    @State private var search = ""

    struct InstalledApp: Identifiable {
        let name: String
        let path: String
        let icon: NSImage
        var id: String { path }
    }

    var body: some View {
        VStack(spacing: 12) {
            modePicker
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
                    Text("Choose a mode to route traffic per app")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
        }
        .task { loadApps() }
        .onChange(of: state.appRoutingMode) { _ in
            Task { await state.reconnectIfConnected() }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App routing")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            Picker("", selection: $state.appRoutingMode) {
                Text("Off").tag(AppRoutingMode.off)
                Text("Selected bypass VPN").tag(AppRoutingMode.bypassSelected)
                Text("Only selected via VPN").tag(AppRoutingMode.onlySelected)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(modeHint)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var modeHint: LocalizedStringKey {
        switch state.appRoutingMode {
        case .off:
            return "All traffic follows the routing mode from Rules"
        case .bypassSelected:
            return "Checked apps connect directly, everything else goes through the VPN"
        case .onlySelected:
            return "Only checked apps go through the VPN, everything else connects directly"
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

    private func loadApps() {
        guard installedApps.isEmpty else { return }
        var apps: [InstalledApp] = []
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications"]
        for dir in dirs {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for item in items where item.hasSuffix(".app") {
                let path = dir + "/" + item
                let name = FileManager.default.displayName(atPath: path)
                    .replacingOccurrences(of: ".app", with: "")
                let icon = NSWorkspace.shared.icon(forFile: path)
                apps.append(InstalledApp(name: name, path: path, icon: icon))
            }
        }
        // Выбранные, но уже удалённые приложения тоже показываем
        for rule in state.appRules where !apps.contains(where: { $0.path == rule.bundlePath }) {
            apps.append(InstalledApp(name: rule.name, bundlePath: rule.bundlePath))
        }
        installedApps = apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private extension MacAppsView.InstalledApp {
    init(name: String, bundlePath: String) {
        self.init(name: name, path: bundlePath, icon: NSWorkspace.shared.icon(forFile: bundlePath))
    }
}
