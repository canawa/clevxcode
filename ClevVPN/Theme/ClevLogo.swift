import SwiftUI

/// Фирменный логотип ClevVPN — «W-корона» (оригинальный векторный ассет бренда).
struct ClevLogo: View {
    var body: some View {
        Image("LogoMark")
            .resizable()
            .scaledToFit()
    }
}

/// Логотип с текстом "ClevVPN".
struct ClevLogoFull: View {
    var logoHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            ClevLogo()
                .frame(height: logoHeight)
            (Text("Clev").foregroundColor(Theme.textPrimary)
                + Text("VPN").foregroundColor(Theme.yellow))
                .font(.system(size: logoHeight * 0.82, weight: .bold, design: .rounded))
        }
    }
}
