import SwiftUI

/// Фирменная палитра ClevVPN: чёрный фон + жёлтая «W-корона».
enum Theme {
    static let background = Color(hex: 0x0B0B0D)
    static let surface = Color(hex: 0x16161A)
    static let surfaceLight = Color(hex: 0x1F1F25)
    static let stroke = Color(hex: 0x2A2A31)

    static let yellow = Color(hex: 0xFFC400)
    static let amber = Color(hex: 0xD18700)
    /// Точный цвет логотипа — для включённой кнопки подключения.
    static let logoYellow = Color(hex: 0xFAC300)
    static let logoAmber = Color(hex: 0xE39A00)
    static let yellowGradient = LinearGradient(
        colors: [yellow, amber],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let textPrimary = Color(hex: 0xF2F2F5)
    static let textSecondary = Color(hex: 0x9A9AA3)

    static let green = Color(hex: 0x30D158)
    static let orange = Color(hex: 0xFF9F0A)
    static let red = Color(hex: 0xFF453A)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Карточка в фирменном стиле.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
