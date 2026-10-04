import SwiftUI
import ClevVPNKit

/// Маршрутизация: режим + пользовательские правила по доменам и IP.
struct RoutingView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAddRule = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        modeSection
                        securitySection
                        rulesSection
                        perAppNote
                    }
                    .padding(16)
                }
            }
            .navigationTitle(Text("Routing"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddRule) {
                AddRuleSheet { rule in
                    state.customRules.append(rule)
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Traffic mode")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            modeRow(.global, title: "All traffic via VPN",
                    subtitle: "Everything goes through the tunnel", icon: "globe")
            modeRow(.smart, title: "Smart mode",
                    subtitle: "Russian sites and local networks connect directly", icon: "brain.head.profile")
            modeRow(.custom, title: "Custom rules only",
                    subtitle: "All traffic via VPN except your rules", icon: "slider.horizontal.3")
        }
    }

    private func modeRow(_ mode: RoutingMode, title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String) -> some View {
        Button {
            state.routingMode = mode
            reconnectIfNeeded()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(state.routingMode == mode ? Theme.yellow : Theme.textSecondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: state.routingMode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(state.routingMode == mode ? Theme.yellow : Theme.stroke)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundColor(state.killSwitchEnabled ? Theme.yellow : Theme.textSecondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
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
                    .tint(Theme.yellow)
            }
            .padding(14)
            .card()
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My rules")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    showAddRule = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(Theme.yellow)
                }
            }

            if state.customRules.isEmpty {
                Text("Add domains or IP addresses that should bypass the VPN or always use it")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            }

            ForEach(state.customRules) { rule in
                HStack(spacing: 12) {
                    Image(systemName: rule.matcher == .domainSuffix ? "network" : "number")
                        .foregroundColor(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.value)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Theme.textPrimary)
                        Text(rule.target == .direct ? "Bypass VPN" : "Via VPN")
                            .font(.caption)
                            .foregroundColor(rule.target == .direct ? Theme.orange : Theme.green)
                    }
                    Spacer()
                    Toggle("", isOn: binding(for: rule))
                        .labelsHidden()
                        .tint(Theme.yellow)
                }
                .padding(14)
                .card()
                .contextMenu {
                    Button(role: .destructive) {
                        state.customRules.removeAll { $0.id == rule.id }
                        reconnectIfNeeded()
                    } label: {
                        Label("Delete rule", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var perAppNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(Theme.yellow)
            Text("iOS does not allow per-app VPN for regular apps — this is an Apple restriction for all VPN clients. Use domain and IP rules instead.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(14)
        .card()
    }

    private func binding(for rule: RoutingRule) -> Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { newValue in
                if let index = state.customRules.firstIndex(where: { $0.id == rule.id }) {
                    state.customRules[index].isEnabled = newValue
                    reconnectIfNeeded()
                }
            }
        )
    }

    private func reconnectIfNeeded() {
        Task { await state.reconnectIfConnected() }
    }
}

/// Форма добавления правила.
struct AddRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (RoutingRule) -> Void

    @State private var value = ""
    @State private var matcher: RoutingRule.Matcher = .domainSuffix
    @State private var target: RoutingRule.Target = .direct

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(matcher == .domainSuffix ? "example.com" : "192.168.1.0/24", text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Picker(selection: $matcher) {
                        Text("Domain").tag(RoutingRule.Matcher.domainSuffix)
                        Text("IP / CIDR").tag(RoutingRule.Matcher.ipCIDR)
                    } label: {
                        Text("Type")
                    }

                    Picker(selection: $target) {
                        Text("Bypass VPN").tag(RoutingRule.Target.direct)
                        Text("Via VPN").tag(RoutingRule.Target.proxy)
                    } label: {
                        Text("Action")
                    }
                } footer: {
                    Text("Domain rules match the domain and all subdomains")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(Text("New rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = value.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onAdd(RoutingRule(value: trimmed, matcher: matcher, target: target))
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
