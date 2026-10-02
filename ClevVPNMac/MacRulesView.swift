import SwiftUI
import ClevVPNKit

/// Режим трафика и правила по доменам/IP (как на iOS).
struct MacRulesView: View {
    @EnvironmentObject private var state: MacState
    @State private var newValue = ""
    @State private var newMatcher: RoutingRule.Matcher = .domainSuffix
    @State private var newTarget: RoutingRule.Target = .direct

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Traffic mode")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                Picker("", selection: $state.routingMode) {
                    Text("All traffic via VPN").tag(RoutingMode.global)
                    Text("Custom rules").tag(RoutingMode.custom)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: state.routingMode) { _ in
                    Task { await state.reconnectIfConnected() }
                }

                Text(modeHint)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)

                Divider().overlay(Theme.stroke)

                Text("Security")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kill Switch")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Blocks all internet if the VPN drops — your real IP never leaks.")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $state.killSwitchEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.yellow)
                }

                Divider().overlay(Theme.stroke)

                Text("My rules")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                HStack(spacing: 8) {
                    TextField(newMatcher == .domainSuffix ? "example.com" : "192.168.1.0/24", text: $newValue)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $newMatcher) {
                        Text("Domain").tag(RoutingRule.Matcher.domainSuffix)
                        Text("IP / CIDR").tag(RoutingRule.Matcher.ipCIDR)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Picker("", selection: $newTarget) {
                        Text("Bypass VPN").tag(RoutingRule.Target.direct)
                        Text("Via VPN").tag(RoutingRule.Target.proxy)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Button {
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        state.customRules.append(RoutingRule(value: trimmed, matcher: newMatcher, target: newTarget))
                        newValue = ""
                        Task { await state.reconnectIfConnected() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Theme.yellow)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(state.customRules) { rule in
                    HStack(spacing: 10) {
                        Image(systemName: rule.matcher == .domainSuffix ? "network" : "number")
                            .foregroundColor(Theme.textSecondary)
                        Text(rule.value)
                            .font(.subheadline)
                            .foregroundColor(Theme.textPrimary)
                        Text(rule.target == .direct ? "Bypass VPN" : "Via VPN")
                            .font(.caption)
                            .foregroundColor(rule.target == .direct ? Theme.orange : Theme.green)
                        Spacer()
                        Toggle("", isOn: binding(for: rule))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .tint(Theme.yellow)
                        Button {
                            state.customRules.removeAll { $0.id == rule.id }
                            Task { await state.reconnectIfConnected() }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(Theme.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .card()
                }
            }
            .padding(20)
        }
    }

    /// Подсказка под выбранным режимом — тот же текст, что на iOS/Windows/Android.
    private var modeHint: LocalizedStringKey {
        switch state.routingMode {
        case .global, .smart:
            // .smart сохранён для iOS; на Mac в UI его нет — ведём себя как global.
            return "All traffic goes through VPN"
        case .custom:
            return "Only your domain/IP rules"
        }
    }

    private func binding(for rule: RoutingRule) -> Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { newValue in
                if let index = state.customRules.firstIndex(where: { $0.id == rule.id }) {
                    state.customRules[index].isEnabled = newValue
                    Task { await state.reconnectIfConnected() }
                }
            }
        )
    }
}

/// Вкладка «Подписка» — общая карточка, одинаковая с iOS/Windows/Android.
struct MacSettingsView: View {
    @EnvironmentObject private var state: MacState
    @State private var showLogoutConfirm = false

    var body: some View {
        SubscriptionSettingsCard(
            title: state.subscription?.title,
            info: state.subscription?.userInfo,
            isLoading: state.isLoading,
            errorMessage: state.errorMessage,
            supportURL: state.subscription?.supportURL,
            onRefresh: { Task { await state.refreshSubscription() } },
            onDelete: { showLogoutConfirm = true },
            onQuit: { state.quit() }
        )
        .confirmationDialog(Text("Remove the access key from this device?"),
                            isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { state.logout() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Экран активации Mac-версии.
struct MacActivationView: View {
    @EnvironmentObject private var state: MacState
    @State private var link = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ClevLogo()
                .frame(width: 110)
            (Text("Clev").foregroundColor(Theme.textPrimary)
                + Text("VPN").foregroundColor(Theme.yellow))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Fast and reliable access without borders")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)

            TextField("Paste your access key", text: $link)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .onSubmit { activate() }

            Button {
                if link.isEmpty,
                   let pasted = NSPasteboard.general.string(forType: .string) {
                    link = pasted
                }
                activate()
            } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(link.isEmpty ? "Paste from clipboard" : "Activate")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 280)
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Theme.yellow)
            .foregroundColor(.black)
            .disabled(state.isLoading)

            if let error = state.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(Theme.red)
            }
            Spacer()
            Text("The key is provided with your subscription")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 30)
    }

    private func activate() {
        guard !link.isEmpty else { return }
        Task { await state.activate(urlString: link) }
    }
}
