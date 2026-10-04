import SwiftUI
import ClevVPNKit

// Визуальные эффекты момента подключения — общие для iOS и macOS.

// MARK: - Расходящиеся волны + вспышка-молния

/// Одноразовый «взрыв» в момент подключения: несколько колец расходятся от
/// кнопки как круги по воде, плюс короткая яркая вспышка. Проигрывается при
/// появлении — родитель вставляет вью, пока `active == true`, и убирает после.
struct ConnectBurst: View {
    /// Диаметр, от которого расходятся кольца (обычно — внешний обод кнопки).
    var diameter: CGFloat

    @State private var rings = false
    @State private var flash = false

    var body: some View {
        ZStack {
            // Волны — три кольца, расходятся со сдвигом по времени
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Theme.logoYellow.opacity(0.55), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(rings ? 1.9 : 1.0)
                    .opacity(rings ? 0 : 0.55)
                    .animation(.easeOut(duration: 1.0).delay(Double(i) * 0.18), value: rings)
            }

            // Вспышка-молния — резкий белый блик из центра
            Circle()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.95), Theme.logoYellow.opacity(0.4), .clear],
                                   center: .center, startRadius: 0, endRadius: diameter * 0.55)
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(flash ? 1.5 : 0.5)
                .opacity(flash ? 0 : 0.9)
                .blendMode(.plusLighter)
                .animation(.easeOut(duration: 0.4), value: flash)

            Image(systemName: "bolt.fill")
                .font(.system(size: diameter * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: Theme.logoYellow, radius: 16)
                .scaleEffect(flash ? 1.35 : 0.5)
                .opacity(flash ? 0 : 1)
                .animation(.easeOut(duration: 0.45), value: flash)
        }
        .allowsHitTesting(false)
        .onAppear {
            rings = true
            flash = true
        }
    }
}

// MARK: - Фоновое свечение под статус

/// Мягкое радиальное свечение за кнопкой, цвет которого плавно меняется под
/// статус: погашено → нейтраль, подключение → янтарь, подключено → зелёно-жёлтое.
struct StatusGlow: View {
    enum Status { case off, busy, on }
    let status: Status

    private var color: Color {
        switch status {
        case .off: return Theme.textSecondary.opacity(0.05)
        case .busy: return Theme.logoAmber.opacity(0.16)
        case .on: return Theme.logoYellow.opacity(0.20)
        }
    }

    var body: some View {
        RadialGradient(colors: [color, .clear],
                       center: .center, startRadius: 0, endRadius: 300)
            .animation(.easeInOut(duration: 0.6), value: status)
            .allowsHitTesting(false)
    }
}
