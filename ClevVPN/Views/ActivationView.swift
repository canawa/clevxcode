import SwiftUI
import ClevVPNKit

/// Экран активации: пользователь вставляет ссылку подписки из бота/личного кабинета.
struct ActivationView: View {
    @EnvironmentObject private var state: AppState
    @State private var link = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ClevLogo()
                .frame(width: 130)
            (Text("Clev").foregroundColor(Theme.textPrimary)
                + Text("VPN").foregroundColor(Theme.yellow))
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Fast and reliable access without borders")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .foregroundColor(Theme.yellow)
                    TextField("Paste your access key", text: $link)
                        .focused($isFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .foregroundColor(Theme.textPrimary)
                        .submitLabel(.go)
                        .onSubmit { activate() }
                    if !link.isEmpty {
                        Button {
                            link = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }
                .padding(16)
                .card()

                Button {
                    if link.isEmpty, let pasted = UIPasteboard.general.string {
                        link = pasted
                    }
                    activate()
                } label: {
                    HStack {
                        if state.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text(link.isEmpty ? "Paste from clipboard" : "Activate")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.yellowGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundColor(.black)
                }
                .disabled(state.isLoading)

                if let error = state.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(Theme.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Text("The key is provided with your subscription")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 12)
        }
        .onTapGesture { isFocused = false }
    }

    private func activate() {
        guard !link.isEmpty else { return }
        Task { await state.activate(urlString: link) }
    }
}
