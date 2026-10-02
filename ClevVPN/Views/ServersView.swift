import SwiftUI
import ClevVPNKit

/// Список серверов: вкладки из админки + избранное + свои папки, поиск и пинг.
struct ServersView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable {
        case all
        case favorites
        case adminGroup(String)
        case folder(UUID)
    }

    @State private var tab: Tab = .all
    @State private var search = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    tabBar
                    serverList
                }
            }
            .navigationTitle(Text("Servers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        state.pingAll()
                    } label: {
                        if state.isPinging {
                            ProgressView().tint(Theme.yellow)
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                                .foregroundColor(Theme.yellow)
                        }
                    }
                    .disabled(state.isPinging)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showNewFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(Theme.yellow)
                    }
                }
            }
            .searchable(text: $search, prompt: Text("Search servers"))
            .refreshable { await state.refreshSubscription() }
            .alert(Text("New folder"), isPresented: $showNewFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") {
                    state.addFolder(named: newFolderName)
                    newFolderName = ""
                }
                Button("Cancel", role: .cancel) { newFolderName = "" }
            }
        }
    }

    // MARK: - Вкладки

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tabChip(.all, label: Text("All"))
                tabChip(.favorites, label: Text("My"))
                ForEach(state.subscription?.adminGroups ?? [], id: \.self) { group in
                    tabChip(.adminGroup(group), label: Text(group))
                }
                ForEach(state.folders) { folder in
                    tabChip(.folder(folder.id), label: Text(verbatim: "📁 \(folder.name)"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func tabChip(_ value: Tab, label: Text) -> some View {
        Button {
            tab = value
        } label: {
            label
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    tab == value ? AnyShapeStyle(Theme.yellowGradient) : AnyShapeStyle(Theme.surface),
                    in: Capsule()
                )
                .foregroundColor(tab == value ? .black : Theme.textSecondary)
        }
        .contextMenu {
            if case .folder(let id) = value {
                Button(role: .destructive) {
                    state.folders.removeAll { $0.id == id }
                    if tab == value { tab = .all }
                } label: {
                    Label("Delete folder", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Список

    private var filteredServers: [Server] {
        var servers = state.servers
        switch tab {
        case .all:
            break
        case .favorites:
            servers = servers.filter { state.favorites.contains($0.id) }
        case .adminGroup(let group):
            servers = servers.filter { $0.group == group }
        case .folder(let id):
            let ids = Set(state.folders.first { $0.id == id }?.serverIDs ?? [])
            servers = servers.filter { ids.contains($0.id) }
        }
        if !search.isEmpty {
            servers = servers.filter {
                $0.rawName.localizedCaseInsensitiveContains(search)
                || $0.host.localizedCaseInsensitiveContains(search)
            }
        }
        return servers
    }

    private var serverList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if filteredServers.isEmpty {
                    Text("No servers here yet")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 60)
                }
                ForEach(filteredServers) { server in
                    ServerRow(
                        server: server,
                        isSelected: state.selectedServer?.id == server.id,
                        isFavorite: state.favorites.contains(server.id),
                        ping: state.pings[server.id]
                    ) {
                        Task {
                            await state.select(server: server)
                            dismiss()
                        }
                    }
                    .contextMenu {
                        Button {
                            state.toggleFavorite(server)
                        } label: {
                            if state.favorites.contains(server.id) {
                                Label("Remove from My", systemImage: "star.slash")
                            } else {
                                Label("Add to My", systemImage: "star")
                            }
                        }
                        ForEach(state.folders) { folder in
                            Button {
                                state.toggle(server: server, in: folder)
                            } label: {
                                if folder.serverIDs.contains(server.id) {
                                    Label(String(localized: "Remove from \(folder.name)"), systemImage: "folder.badge.minus")
                                } else {
                                    Label(String(localized: "Add to \(folder.name)"), systemImage: "folder.badge.plus")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
}

struct ServerRow: View {
    let server: Server
    let isSelected: Bool
    let isFavorite: Bool
    let ping: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(server.flagEmoji ?? "🌐")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(Theme.yellow)
                        }
                        Text(server.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    Text(server.protocolType.displayName)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceLight, in: Capsule())
                        .foregroundColor(Theme.yellow)
                }

                Spacer()

                if let ping, ping >= 0 {
                    PingLabel(ms: ping)
                } else if ping == -1 {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(Theme.red)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.yellow)
                }
            }
            .padding(14)
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Theme.yellow.opacity(0.6) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
