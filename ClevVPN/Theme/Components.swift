import SwiftUI
import UniformTypeIdentifiers
import ClevVPNKit

// Компоненты, общие для iOS- и macOS-версий.

/// Лента перетаскиваемых вкладок-групп. Массив НЕ меняется во время drag —
/// двигаются только визуальные смещения (перетаскиваемая под курсором, соседи
/// расступаются), а порядок фиксируется один раз при отпускании через `onReorder`.
/// Так нет рассинхрона layout ↔ offset (никакого «оттягивания назад»).
struct ReorderableTabStrip: View {
    let groups: [String]
    let isSelected: (String) -> Bool
    /// Заголовок элемента: для групп — имя, для спец-токена «Мои» — локализованный.
    var title: (String) -> Text = { Text(verbatim: $0) }
    var compact: Bool = false
    let onTap: (String) -> Void
    let onReorder: ([String]) -> Void

    @State private var dragging: String? = nil
    @State private var dragOffset: CGFloat = 0

    private var stride: CGFloat { compact ? 62 : 80 }

    private var draggingIndex: Int? { dragging.flatMap { groups.firstIndex(of: $0) } }

    /// Целевая позиция перетаскиваемой вкладки по текущему смещению.
    private var targetIndex: Int? {
        guard let di = draggingIndex else { return nil }
        let steps = Int((dragOffset / stride).rounded())
        return max(0, min(groups.count - 1, di + steps))
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            ForEach(groups, id: \.self) { g in
                chip(g)
            }
        }
    }

    /// Визуальное смещение вкладки: перетаскиваемая — под курсором; соседи между
    /// старой и новой позицией сдвигаются на шаг, освобождая место.
    private func offsetFor(_ g: String) -> CGFloat {
        guard let di = draggingIndex, let ti = targetIndex else { return 0 }
        if g == dragging { return dragOffset }
        guard let gi = groups.firstIndex(of: g) else { return 0 }
        if di < ti, gi > di, gi <= ti { return -stride }
        if di > ti, gi < di, gi >= ti { return stride }
        return 0
    }

    private func chip(_ g: String) -> some View {
        let isDrag = dragging == g
        return title(g)
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 4 : 7)
            .background(
                isSelected(g) ? AnyShapeStyle(Theme.yellowGradient) : AnyShapeStyle(Theme.surface),
                in: Capsule()
            )
            .foregroundColor(isSelected(g) ? .black : Theme.textSecondary)
            .overlay(Capsule().strokeBorder(Theme.yellow.opacity(isDrag ? 0.9 : 0), lineWidth: 1.5))
            .contentShape(Capsule())
            .scaleEffect(isDrag ? 1.05 : 1)
            .offset(x: offsetFor(g))
            .zIndex(isDrag ? 1 : 0)
            // Соседи плавно расступаются (по смене целевой позиции); сама
            // перетаскиваемая следует за курсором без анимации.
            .animation(isDrag ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: targetIndex)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
            .onTapGesture { if dragging == nil { onTap(g) } }
            .gesture(reorderGesture(g))
    }

    /// Жест перетаскивания вкладки.
    /// iOS: сначала долгое нажатие (иначе горизонтальный свайп ЛИСТАЕТ ленту, а
    /// не таскает вкладку). macOS: сдвиг на >8pt — трекпад листает по-другому.
    private func reorderGesture(_ g: String) -> some Gesture {
        #if os(iOS)
        let drag = DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                if dragging == nil { dragging = g }
                dragOffset = drag.translation.width
            }
            .onEnded { _ in endDrag() }
        return LongPressGesture(minimumDuration: 0.3).sequenced(before: drag)
        #else
        return DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { drag in
                if dragging == nil { dragging = g }
                dragOffset = drag.translation.width
            }
            .onEnded { _ in endDrag() }
        #endif
    }

    private func endDrag() {
        // Перестановка массива и сброс смещения — в ОДНОЙ не-анимированной
        // транзакции, иначе вкладку «дёргает».
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if let di = draggingIndex, let ti = targetIndex, di != ti {
                var arr = groups
                let item = arr.remove(at: di)
                arr.insert(item, at: ti)
                onReorder(arr)
            }
            dragOffset = 0
            dragging = nil
        }
    }
}

/// Кнопка подключения: вогнутая «тарелка» по центру, которая загорается,
/// анимация линий по ободку при включении, минималистичный таймер сессии,
/// тактильное «продавливание» при нажатии.
struct ConnectButton: View {
    enum Status { case off, busy, on }
    let state: Status
    var size: CGFloat = 180
    /// Момент подключения — для таймера часы:минуты:секунды.
    var connectedAt: Date? = nil
    /// Идёт замер пинга — крутится линия по ободку и подпись «Проверка пинга».
    var isPinging: Bool = false
    let action: () -> Void

    /// Показывать «пинг-индикацию» только когда не заняты подключением.
    private var showPing: Bool { isPinging && state == .off }

    @State private var spin = false
    @State private var ringFill: CGFloat = 0   // 0…1 — заполнение ободка
    @State private var cometAngle: Double = -90 // угол кометы при включении
    @State private var burst = false            // одноразовые волны + вспышка

    private var ringSize: CGFloat { size + 24 }

    var body: some View {
        Button(action: action) {
            ZStack {
                if burst { ConnectBurst(diameter: ringSize).zIndex(2) }
                outerLine       // внешняя линия: одна плавная линия по кругу
                rim             // приподнятый тёмный ободок
                plate           // вогнутая тарелка (загорается при подключении)
                content         // иконка + подпись/таймер
            }
            .frame(width: ringSize + 8, height: ringSize + 8)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.easeInOut(duration: 0.3), value: state == .on)
        .onChange(of: state == .on) { isOn in
            if isOn {
                // Комета-сегмент стремительно проносится ~2.5 оборота за 0.55с,
                // одновременно ободок загорается — ощущение скорости.
                ringFill = 0
                cometAngle = -90
                withAnimation(.easeIn(duration: 0.5)) { cometAngle = -90 + 900 }
                withAnimation(.easeOut(duration: 0.55).delay(0.15)) { ringFill = 1 }
                // Волны по воде + вспышка-молния; убираем вью после проигрыша.
                burst = false
                DispatchQueue.main.async { burst = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { burst = false }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { ringFill = 0 }
                cometAngle = -90
                burst = false
            }
        }
        .onAppear { if state == .on { ringFill = 1 } }
    }

    // MARK: - Внешняя линия

    @ViewBuilder
    private var outerLine: some View {
        // Базовая тусклая дорожка
        Circle()
            .stroke(Theme.stroke.opacity(0.55), lineWidth: 1.5)
            .frame(width: ringSize, height: ringSize)

        if state == .on {
            // Загоревшийся ободок (заполняется по мере ringFill)
            Circle()
                .trim(from: 0, to: ringFill)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Theme.logoYellow, Theme.logoAmber, Theme.logoYellow]),
                        center: .center),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.logoYellow.opacity(0.5), radius: 4)

            // Комета: яркая голова с затухающим хвостом, стремительно летит по кругу
            Circle()
                .trim(from: 0, to: 0.18)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, Theme.logoYellow.opacity(0.7), .white]),
                        center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(cometAngle))
                .shadow(color: Theme.logoYellow.opacity(0.9), radius: 6)
                .opacity(ringFill < 1 ? 1 : 0)   // гаснет, когда ободок загорелся
        } else if state == .busy || showPing {
            // Подключение / замер пинга — линия наматывает круги по ободку.
            Circle()
                .trim(from: 0, to: 0.2)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, Theme.logoAmber.opacity(0.5), .white]),
                        center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .shadow(color: Theme.logoYellow.opacity(0.7), radius: 5)
                .onAppear {
                    spin = false
                    // Пинг — чуть спокойнее, подключение — быстрее
                    withAnimation(.linear(duration: showPing ? 0.9 : 0.5).repeatForever(autoreverses: false)) { spin = true }
                }
                .onDisappear { spin = false }
        }
    }

    // MARK: - Ободок

    private var rim: some View {
        Circle()
            .fill(
                LinearGradient(colors: [Color(hex: 0x30303A), Color(hex: 0x121217)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
            .shadow(color: glowColor, radius: 30)
    }

    // MARK: - Вогнутая тарелка

    private var plate: some View {
        let plateSize = size * 0.74
        // Вогнутая «чаша»: радиальный градиент темнеет к краю (центр ярче),
        // центр смещён вверх — свет падает сверху. Плюс блик по верхнему краю
        // и чёткая тёмная окантовка. Так вогнутость видна на любом цвете.
        return Circle()
            .fill(plateRadial(diameter: plateSize))
            .overlay(
                // Блик — свет отражается от верхнего края чаши
                Circle()
                    .fill(LinearGradient(colors: [plateTopLight, .clear],
                                         startPoint: .top,
                                         endPoint: UnitPoint(x: 0.5, y: 0.45)))
                    .blendMode(.plusLighter)
            )
            .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1.5))
            .clipShape(Circle())
            .frame(width: plateSize, height: plateSize)
            .shadow(color: state == .on ? Theme.logoYellow.opacity(0.4) : .clear, radius: 12)
    }

    private func plateRadial(diameter: CGFloat) -> RadialGradient {
        let center = UnitPoint(x: 0.5, y: 0.42)   // свет чуть сверху
        switch state {
        case .on:
            return RadialGradient(colors: [Theme.logoYellow, Theme.logoAmber],
                                  center: center, startRadius: diameter * 0.05, endRadius: diameter * 0.6)
        case .busy, .off:
            return RadialGradient(colors: [Color(hex: 0x24242E), Color(hex: 0x0C0C11)],
                                  center: center, startRadius: diameter * 0.05, endRadius: diameter * 0.6)
        }
    }
    private var plateTopLight: Color {
        state == .on ? .white.opacity(0.3) : .white.opacity(0.10)
    }

    // MARK: - Контент

    private var content: some View {
        VStack(spacing: state == .on ? 7 : 6) {
            Image(systemName: "power")
                .font(.system(size: size * 0.22, weight: .light))
                .foregroundStyle(iconStyle)
                .shadow(color: state == .on ? .black.opacity(0.2) : .clear, radius: 1, y: 1)

            if state == .on {
                VStack(spacing: 3) {
                    Text(label)
                        .font(.system(size: size * 0.058, weight: .regular))
                        .tracking(3)                 // больше воздуха = минималистичнее
                        .foregroundColor(.black.opacity(0.45))
                    if let connectedAt {
                        TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                            Text(Self.elapsed(from: connectedAt, now: context.date))
                                .font(.system(size: size * 0.11, weight: .light, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.black.opacity(0.7))
                        }
                    }
                }
            } else {
                Text(label)
                    .font(.system(size: size * 0.075, weight: .regular))
                    .tracking(1)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private static func elapsed(from start: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    // MARK: - Стили по состоянию

    private var glowColor: Color {
        switch state {
        case .on: return Theme.logoYellow.opacity(0.35)
        case .busy: return Theme.logoYellow.opacity(0.12)
        case .off: return .clear
        }
    }

    private var iconStyle: AnyShapeStyle {
        if showPing { return AnyShapeStyle(Theme.logoYellow) }
        switch state {
        case .on: return AnyShapeStyle(Color.black.opacity(0.75))
        case .busy: return AnyShapeStyle(Theme.logoYellow)
        case .off: return AnyShapeStyle(Theme.textSecondary)
        }
    }

    private var label: LocalizedStringKey {
        if showPing { return "Checking ping…" }
        switch state {
        case .on: return "CONNECTED"
        case .busy: return "Connecting…"
        case .off: return "Start"
        }
    }
}

/// Стиль кнопки с «продавливанием»: масштаб уменьшается при нажатии.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Пинг с цветовой индикацией.
struct PingLabel: View {
    let ms: Int

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(ms) ms")
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var color: Color {
        switch ms {
        case ..<120: return Theme.green
        case ..<300: return Theme.orange
        default: return Theme.red
        }
    }
}

/// Компактная строка сервера.
struct QuickServerRow: View {
    let server: Server
    let isSelected: Bool
    let isFavorite: Bool
    let ping: Int?
    var isPinging: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(server.flagEmoji ?? "🌐")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(Theme.yellow)
                        }
                        Text(server.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)

                        Text(server.protocolType.displayName)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.surfaceLight, in: Capsule())
                            .foregroundColor(Theme.yellow)
                    }
                    // Server Description из панели — под названием сервера
                    if let description = server.descriptionText, !description.isEmpty {
                        Text(description)
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isPinging {
                    ProgressView().controlSize(.small)
                } else if let ping, ping >= 0 {
                    PingLabel(ms: ping)
                } else if ping == -1 {
                    Text(verbatim: "—")
                        .font(.caption)
                        .foregroundColor(Theme.red)
                }

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.subheadline)
                    .foregroundColor(isSelected ? Theme.yellow : Theme.stroke)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? Theme.yellow.opacity(0.65) : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Строка режима «Авто»: ядро само держит самый быстрый сервер.
struct AutoServerRow: View {
    let isSelected: Bool
    let fastest: Server?
    let ping: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.yellowGradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto — fastest server")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    if let fastest {
                        Text(verbatim: "\(fastest.flagEmoji ?? "🌐") \(fastest.name)")
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                    } else {
                        Text("Switches automatically by ping")
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Spacer()

                if let ping, ping >= 0 {
                    PingLabel(ms: ping)
                }

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.subheadline)
                    .foregroundColor(isSelected ? Theme.yellow : Theme.stroke)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(Theme.yellowGradient) : AnyShapeStyle(Theme.stroke), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Полоса с данными подписки: трафик и срок действия.
struct SubscriptionInfoBar: View {
    let info: SubscriptionUserInfo?

    var body: some View {
        if let info {
            HStack(spacing: 16) {
                if let used = info.usedBytes {
                    Label {
                        if let total = info.totalBytes, total > 0 {
                            Text(verbatim: "\(format(used)) / \(format(total))")
                        } else {
                            Text(verbatim: format(used))
                        }
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                Spacer()
                if let expires = info.expiresAt {
                    Label {
                        Text(expires, style: .date)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .font(.caption)
            .foregroundColor(Theme.textSecondary)
            .padding(10)
            .card()
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
