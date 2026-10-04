import SwiftUI
import ClevVPNKit

/// Настройки: язык, подписка, поддержка, о приложении.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("appLanguage") private var appLanguage = "system"
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        subscriptionSection
                        languageSection
                        aboutSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Подписка

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            VStack(spacing: 0) {
                if let title = state.subscription?.title, !title.isEmpty {
                    row(icon: "person.crop.circle", title: Text(title))
                    Divider().overlay(Theme.stroke)
                }
                if let info = state.subscription?.userInfo {
                    if let used = info.usedBytes {
                        row(icon: "arrow.up.arrow.down",
                            title: Text("Traffic used"),
                            value: trafficText(used: used, total: info.totalBytes))
                        Divider().overlay(Theme.stroke)
                    }
                    if let expires = info.expiresAt {
                        row(icon: "calendar",
                            title: Text("Active until"),
                            value: Text(expires, style: .date))
                        Divider().overlay(Theme.stroke)
                    }
                }
                Button {
                    Task { await state.refreshSubscription() }
                } label: {
                    row(icon: "arrow.clockwise",
                        title: Text("Update subscription"),
                        showsChevron: false,
                        isLoading: state.isLoading)
                }
                Divider().overlay(Theme.stroke)
                Button {
                    showLogoutConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(Theme.red)
                            .frame(width: 26)
                        Text("Remove key and sign out")
                            .font(.subheadline)
                            .foregroundColor(Theme.red)
                        Spacer()
                    }
                    .padding(14)
                }
            }
            .card()
        }
        .confirmationDialog(Text("Remove the access key from this device?"),
                            isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { state.logout() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func trafficText(used: Int64, total: Int64?) -> Text {
        let usedStr = ByteCountFormatter.string(fromByteCount: used, countStyle: .binary)
        if let total, total > 0 {
            let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .binary)
            return Text(verbatim: "\(usedStr) / \(totalStr)")
        }
        return Text(verbatim: usedStr)
    }

    // MARK: - Язык

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            VStack(spacing: 0) {
                languageRow("system", title: Text("System"))
                Divider().overlay(Theme.stroke)
                languageRow("ru", title: Text(verbatim: "Русский"))
                Divider().overlay(Theme.stroke)
                languageRow("en", title: Text(verbatim: "English"))
            }
            .card()
        }
    }

    private func languageRow(_ code: String, title: Text) -> some View {
        Button {
            guard appLanguage != code else { return }
            appLanguage = code
            if code == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            }
        } label: {
            HStack(spacing: 12) {
                title
                    .font(.subheadline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if appLanguage == code {
                    Image(systemName: "checkmark")
                        .foregroundColor(Theme.yellow)
                }
            }
            .padding(14)
        }
    }

    // MARK: - О приложении

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            VStack(spacing: 0) {
                if let support = state.subscription?.supportURL, let url = URL(string: support) {
                    Link(destination: url) {
                        row(icon: "questionmark.circle", title: Text("Support"))
                    }
                    Divider().overlay(Theme.stroke)
                }
                row(icon: "shield.checkerboard",
                    title: Text("Version"),
                    value: Text(verbatim: appVersion),
                    showsChevron: false)
            }
            .card()

            HStack {
                Spacer()
                ClevLogoFull(logoHeight: 18)
                    .opacity(0.5)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "ClevVPN \(version)"
    }

    // MARK: - Строка настроек

    private func row(icon: String, title: Text, value: Text? = nil,
                     showsChevron: Bool = false, isLoading: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.yellow)
                .frame(width: 26)
            title
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            if isLoading {
                ProgressView().tint(Theme.yellow)
            } else if let value {
                value
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(14)
    }
}
