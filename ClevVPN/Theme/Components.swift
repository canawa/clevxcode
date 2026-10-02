import SwiftUI
import UniformTypeIdentifiers
import ClevVPNKit

// Компоненты, общие для iOS- и macOS-версий.
// Геометрия и цвета сверены с эталонными Android- и Windows-приложениями
// (ClevComponents.kt / ClevVPN.Controls) — вид одинаковый на всех платформах.

// MARK: - Вкладки настроек

/// Вкладки настроек — одинаковый набор, порядок и названия на всех платформах.
enum SettingsTab: String, CaseIterable, Hashable {
    #if os(macOS)
    /// Маршрутизация по приложениям есть только на macOS — на iOS Apple её не даёт.
    case apps
    #endif
    case rules
    case subscription
    case language

    var titleKey: LocalizedStringKey {
        switch self {
        #if os(macOS)
        case .apps: return "Apps"
        #endif
        case .rules: return "Rules"
        case .subscription: return "Subscription"
        case .language: return "Language"
        }
    }
}

/// Сегментированные вкладки настроек — порт ClevSegmentedTabs из эталона:
/// скруглённый контейнер, выбранная вкладка — жёлтая «пилюля» с чёрным текстом,
/// между невыбранными соседями — тонкий разделитель. В отличие от нативного
/// сегмент-контрола названия не обрезаются.
struct ClevSegmentedTabs: View {
    @Binding var selection: SettingsTab

    private let tabs = SettingsTab.allCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    // Без minimumScaleFactor: при открытии окна настроек раскладка
                    // на миг пересчитывается, и авто-уменьшение «дёргало» подписи.
                    Text(tab.titleKey)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selected ? .black : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selected ? AnyShapeStyle(Theme.yellow) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) {
                    // Разделитель только между двумя невыбранными соседями
                    if index > 0, !selected, selection != tabs[index - 1] {
                        Rectangle()
                            .fill(Theme.stroke)
                            .frame(width: 1, height: 14)
                    }
                }
            }
        }
        .padding(4)
        .background(Theme.surfaceLight, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Сегментный переключатель режима в стиле вкладок настроек. Сегменты равной
/// ширины, длинная подпись переносится на вторую строку — поэтому он никогда не
/// шире окна (системный сегмент-контрол на длинных русских подписях вылезал за
/// края, и весь блок обрезался с обеих сторон).
struct ClevSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? .black : Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            selected ? AnyShapeStyle(Theme.yellow) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) {
                    // Разделитель только между двумя невыбранными соседями
                    if index > 0, !selected, selection != options[index - 1].value {
                        Rectangle()
                            .fill(Theme.stroke)
                            .frame(width: 1, height: 14)
                    }
                }
            }
        }
        // Все сегменты — одной высоты (по самому высокому)
        .fixedSize(horizontal: false, vertical: true)
        .padding(3)
        .background(Theme.surfaceLight, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Вкладки Home

/// Фильтр списка серверов на Home: «Все» + фиксированные категории.
/// Набор и названия вкладок одинаковые на iOS, macOS, Windows и Android.
enum HomeFilter: Hashable {
    case all
    case category(ServerCategory)

    /// Стабильный id для сохранения пользовательского порядка (как на Windows).
    var id: String {
        switch self {
        case .all: return "ALL"
        case .category(let category): return category.rawValue.uppercased()
        }
    }

    func apply(to servers: [Server]) -> [Server] {
        switch self {
        case .all:
            return servers
        case .category(let category):
            return servers.filter { category.matches($0.rawName) }
        }
    }

    /// Порядок по умолчанию: «Все», затем категории (без «Авто»).
    static let defaultOrder: [HomeFilter] = [.all] + ServerCategory.homeFilters.map(HomeFilter.category)

    /// Вкладки в пользовательском порядке; неизвестные/новые — в конец
    /// (порт `ServerCategoryHelper.OrderedFilters` из Windows-версии).
    static func ordered(_ savedOrder: [String]) -> [HomeFilter] {
        var remaining = defaultOrder
        var result: [HomeFilter] = []
        for id in savedOrder {
            if let index = remaining.firstIndex(where: { $0.id == id }) {
                result.append(remaining.remove(at: index))
            }
        }
        result.append(contentsOf: remaining)
        return result
    }
}

extension ServerCategory {
    /// Названия вкладок — те же, что в strings.xml эталонных версий.
    var titleKey: LocalizedStringKey {
        switch self {
        case .bypass: return "Bypass"
        case .auto: return "⚡ Auto"
        case .speed: return "Speed"
        case .youtube: return "YouTube"
        case .gaming: return "Gaming"
        }
    }
}

/// Лента вкладок Home. Порядок меняется перетаскиванием и сохраняется между
/// запусками (как на Windows). Массив НЕ меняется во время перетаскивания —
/// двигаются только визуальные смещения, порядок фиксируется при отпускании,
/// поэтому нет рассинхрона layout ↔ offset.
struct HomeFilterChips: View {
    @Binding var filter: HomeFilter
    /// Сохранённый порядок вкладок (id); пустой — порядок по умолчанию.
    var order: [String] = []
    /// Новый порядок после перетаскивания.
    var onReorder: ([String]) -> Void = { _ in }
    var compact: Bool = false
    var horizontalPadding: CGFloat = 20

    @State private var dragging: HomeFilter? = nil
    @State private var dragOffset: CGFloat = 0

    private var filters: [HomeFilter] { HomeFilter.ordered(order) }
    private var stride: CGFloat { compact ? 62 : 80 }
    private var draggingIndex: Int? { dragging.flatMap { filters.firstIndex(of: $0) } }

    /// Целевая позиция перетаскиваемой вкладки по текущему смещению.
    private var targetIndex: Int? {
        guard let from = draggingIndex else { return nil }
        let steps = Int((dragOffset / stride).rounded())
        return max(0, min(filters.count - 1, from + steps))
    }

    var body: some View {
        #if os(macOS)
        if compact {
            scrollingRow
        } else {
            // В окне Mac вкладки крупнее и растянуты на всю ширину — без пустого
            // места сбоку. Одна раскладка, без переключений — ничего не дёргается.
            chipsRow(stretch: true)
        }
        #else
        scrollingRow
        #endif
    }

    private var scrollingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            chipsRow(stretch: false)
        }
    }

    private func chipsRow(stretch: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            ForEach(filters, id: \.self) { item in
                chip(item, stretch: stretch)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 5)
    }

    /// Визуальное смещение: перетаскиваемая — под курсором, соседи между старой
    /// и новой позицией сдвигаются на шаг, освобождая место.
    private func offset(for item: HomeFilter) -> CGFloat {
        guard let from = draggingIndex, let to = targetIndex else { return 0 }
        if item == dragging { return dragOffset }
        guard let index = filters.firstIndex(of: item) else { return 0 }
        if from < to, index > from, index <= to { return -stride }
        if from > to, index < from, index >= to { return stride }
        return 0
    }

    private func chip(_ item: HomeFilter, stretch: Bool) -> some View {
        let selected = filter == item
        let isDrag = dragging == item
        return label(for: item)
            .font(stretch ? Font.system(size: 12, weight: .medium)
                          : (compact ? Font.caption2 : Font.caption).weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, stretch ? 6 : (compact ? 9 : 12))
            .padding(.vertical, stretch ? 7 : (compact ? 4 : 7))
            .frame(maxWidth: stretch ? .infinity : nil)
            .background(
                selected ? AnyShapeStyle(Theme.yellowGradient) : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
            .foregroundColor(selected ? .black : Theme.textSecondary)
            .overlay(Capsule().strokeBorder(Theme.yellow.opacity(isDrag ? 0.9 : 0), lineWidth: 1.5))
            .contentShape(Capsule())
            .scaleEffect(isDrag ? 1.05 : 1)
            .offset(x: offset(for: item))
            .zIndex(isDrag ? 1 : 0)
            .animation(isDrag ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: targetIndex)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
            .onTapGesture { if dragging == nil { filter = item } }
            .gesture(reorderGesture(item))
    }

    private func label(for item: HomeFilter) -> Text {
        switch item {
        case .all: return Text("All")
        case .category(let category): return Text(category.titleKey)
        }
    }

    /// iOS: сначала долгое нажатие — иначе горизонтальный свайп таскал бы вкладку
    /// вместо прокрутки ленты. macOS: достаточно сдвига на 8pt.
    private func reorderGesture(_ item: HomeFilter) -> some Gesture {
        #if os(iOS)
        let drag = DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragging == nil { dragging = item }
                dragOffset = value.translation.width
            }
            .onEnded { _ in endDrag() }
        return LongPressGesture(minimumDuration: 0.3).sequenced(before: drag)
        #else
        return DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if dragging == nil { dragging = item }
                dragOffset = value.translation.width
            }
            .onEnded { _ in endDrag() }
        #endif
    }

    private func endDrag() {
        // Перестановка и сброс смещения — в ОДНОЙ не-анимированной транзакции,
        // иначе вкладку «дёргает».
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let from = draggingIndex, let to = targetIndex, from != to {
                var updated = filters
                let item = updated.remove(at: from)
                updated.insert(item, at: to)
                onReorder(updated.map(\.id))
            }
            dragOffset = 0
            dragging = nil
        }
    }
}

// MARK: - Кнопка подключения

/// Кнопка подключения: утопленный 3D-колодец, который загорается при
/// подключении, кольцо-комета на старте, таймер сессии и «продавливание» при
/// нажатии. Геометрия и цвета — 1:1 с `ClevConnectButton` эталона.
struct ConnectButton: View {
    enum Status { case off, busy, on }
    let state: Status
    var size: CGFloat = 180
    /// Момент подключения — для таймера часы:минуты:секунды.
    var connectedAt: Date? = nil
    /// Идёт замер пинга — линия крутится по ободку.
    var isPinging: Bool = false
    let action: () -> Void

    /// «Пинг-индикация» только когда не заняты подключением.
    private var showPing: Bool { isPinging && state == .off }
    private var showRingSpinner: Bool { state == .busy || showPing }
    private var isOn: Bool { state == .on }

    @State private var spin = false
    @State private var ringFill: CGFloat = 0
    @State private var cometAngle: Double = -90
    @State private var showComet = false
    @State private var burst = false

    private var ringSize: CGFloat { size + 24 }

    var body: some View {
        Button(action: action) {
            ZStack {
                if burst { ConnectBurst(diameter: ringSize).zIndex(2) }
                outerRings      // три бледных кольца снаружи
                trackRing       // дорожка + заполнение + комета + спиннер
                plate           // 3D-колодец
                content         // иконка + подпись/таймер
            }
            .frame(width: ringSize + 8, height: ringSize + 8)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onChange(of: isOn) { on in
            if on {
                // Комета проносится ~2.5 оборота за 0.5с, одновременно
                // загорается ободок — ощущение скорости.
                ringFill = 0
                cometAngle = -90
                showComet = true
                withAnimation(.easeIn(duration: 0.5)) { cometAngle = 810 }
                withAnimation(.easeInOut(duration: 0.55).delay(0.15)) { ringFill = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { showComet = false }
                // Волны по воде + вспышка; вью убираем после проигрыша.
                burst = false
                DispatchQueue.main.async { burst = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { burst = false }
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { ringFill = 0 }
                cometAngle = -90
                showComet = false
                burst = false
            }
        }
        .onAppear { if isOn { ringFill = 1 } }
    }

    // MARK: Кольца снаружи

    private var outerRings: some View {
        ZStack {
            ForEach(Array([0.98, 0.88, 0.78].enumerated()), id: \.offset) { index, scale in
                Circle()
                    .stroke(Theme.stroke.opacity(0.35 - Double(index) * 0.08), lineWidth: 1)
                    .frame(width: (ringSize + 4) * scale, height: (ringSize + 4) * scale)
            }
        }
    }

    // MARK: Дорожка ободка

    @ViewBuilder
    private var trackRing: some View {
        Circle()
            .stroke(Theme.stroke.opacity(0.55), lineWidth: 3)
            .frame(width: ringSize, height: ringSize)

        if isOn, ringFill > 0 {
            Circle()
                .trim(from: 0, to: ringFill)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Theme.logoYellow, Theme.logoAmber, Theme.logoYellow]),
                        center: .center),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
        }

        if showComet, ringFill < 1 {
            Circle()
                .trim(from: 0, to: 0.18)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, Theme.logoYellow.opacity(0.7), .white]),
                        center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(cometAngle - 90))
        }

        if showRingSpinner {
            // 72° — как sweepAngle в эталоне
            Circle()
                .trim(from: 0, to: 0.2)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, Theme.logoAmber.opacity(0.5), .white]),
                        center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(spin ? 270 : -90))
                .onAppear {
                    spin = false
                    // Пинг — спокойнее (0.9с), подключение — быстрее (0.5с)
                    withAnimation(.linear(duration: showPing ? 0.9 : 0.5).repeatForever(autoreverses: false)) {
                        spin = true
                    }
                }
                .onDisappear { spin = false }
        }
    }

    // MARK: 3D-колодец

    /// Цвета слоёв колодца: выключено → включено. Значения — те же смеси
    /// (`lerp`), что в эталоне, посчитанные для крайних состояний.
    private var bezelHigh: Color { isOn ? Color(hex: 0xC9B374) : Color(hex: 0x4A4A54) }
    private var bezelLow: Color { isOn ? Color(hex: 0xB77704) : Color(hex: 0x141418) }
    private var wellTop: Color { isOn ? Color(hex: 0x785303) : Color(hex: 0x07070A) }
    private var wellBottom: Color { isOn ? Color(hex: 0xCA9B22) : Color(hex: 0x22222C) }
    private var floorHigh: Color { isOn ? Color(hex: 0xF5C400) : Color(hex: 0x2C2C36) }
    private var floorLow: Color { isOn ? Color(hex: 0xE8A200) : Color(hex: 0x16161C) }
    private var insetShadowAlpha: Double { isOn ? 0.3575 : 0.55 }
    private var rimGlowAlpha: Double { isOn ? 0.12 : 0.06 }

    private var plate: some View {
        let d = size
        let wellInset = d * 0.055
        let floorInset = d * 0.13

        return ZStack {
            // Скос обода: свет сверху-слева → тень снизу-справа
            Circle()
                .fill(LinearGradient(colors: [bezelHigh, bezelLow],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            // Стенка колодца: тёмный верх = «углубление вниз»
            Circle()
                .fill(LinearGradient(colors: [wellTop, wellBottom],
                                     startPoint: UnitPoint(x: 0.15, y: 0),
                                     endPoint: UnitPoint(x: 0.85, y: 1)))
                .padding(wellInset)

            // Inner-shadow по верхней кромке
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(insetShadowAlpha), location: 0.35),
                            .init(color: .black.opacity(insetShadowAlpha), location: 0.55),
                            .init(color: .clear, location: 0.75),
                            .init(color: .clear, location: 1)
                        ]),
                        center: .center),
                    lineWidth: d * 0.07)
                .padding(wellInset)

            // Пол — блик сверху-слева
            Circle()
                .fill(RadialGradient(colors: [floorHigh, floorLow],
                                     center: UnitPoint(x: 0.38, y: 0.34),
                                     startRadius: 0,
                                     endRadius: (d / 2 - floorInset * 0.55)))
                .padding(floorInset)

            // Мягкий блик на нижнем правом ободе
            Circle()
                .trim(from: 20.0 / 360.0, to: 90.0 / 360.0)
                .stroke(.white.opacity(rimGlowAlpha),
                        style: StrokeStyle(lineWidth: d * 0.035, lineCap: .round))
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.55), radius: 14, y: 4)
        .animation(.easeInOut(duration: 0.3), value: isOn)
    }

    // MARK: Контент

    private var content: some View {
        VStack(spacing: isOn ? 7 : 6) {
            Image(systemName: "power")
                .font(.system(size: size * 0.22, weight: .regular))
                .foregroundStyle(iconStyle)

            if isOn {
                VStack(spacing: 3) {
                    Text(label)
                        .font(.system(size: size * 0.058, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.black.opacity(0.45))
                    if let connectedAt {
                        TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                            Text(Self.elapsed(from: connectedAt, now: context.date))
                                .font(.system(size: size * 0.11, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(.black.opacity(0.7))
                        }
                    }
                }
            } else {
                Text(label)
                    .font(.system(size: size * (state == .busy ? 0.055 : 0.075), weight: .bold))
                    .tracking(state == .busy ? 0 : 1)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, size * 0.08)
    }

    /// `h:mm:ss`, а меньше часа — `mm:ss` (как formatSession в эталоне).
    private static func elapsed(from start: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
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
        // Во время замера пинга подпись НЕ меняется — крутится только линия по
        // ободку (в эталоне отдельной подписи на кнопке для пинга нет).
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

// MARK: - Строка сервера

/// Пинг с цветовой точкой.
struct PingLabel: View {
    let ms: Int

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(ms) ms")
                .font(.system(size: 12))
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

/// Индикатор выбора: жёлтое кольцо с точкой у выбранного, бледное — у остальных
/// (порт ClevSelectionIndicator).
struct ClevSelectionIndicator: View {
    let selected: Bool
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? Theme.yellow : Theme.stroke.opacity(0.5),
                              lineWidth: size * (selected ? 0.09 : 0.07))
            if selected {
                Circle()
                    .fill(Theme.yellow)
                    .frame(width: size * 0.44, height: size * 0.44)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Строка сервера: флаг, название, под названием — бейдж протокола, справа пинг
/// и индикатор выбора (порт QuickServerRow + ServerTitleWithProtocolBadge).
/// На iOS — размеры эталона; на macOS строки компактнее (узкое окно, длинный список).
struct QuickServerRow: View {
    let server: Server
    let isSelected: Bool
    let isFavorite: Bool
    let ping: Int?
    var isPinging: Bool = false
    let onTap: () -> Void

    #if os(macOS)
    private let compact = true
    #else
    private let compact = false
    #endif

    /// Имя без лишних пробелов из панели («Европа  | WIFI» → «Европа | WIFI»).
    private var displayName: String {
        server.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private var serverDescription: String? {
        guard let text = server.descriptionText, !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(server.flagEmoji ?? "🌐")
                    .font(.system(size: compact ? 16 : 22))

                HStack(spacing: 4) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: compact ? 10 : 12))
                            .foregroundColor(Theme.yellow)
                            .frame(width: compact ? 14 : 22, height: compact ? 14 : 22)
                    }
                    if compact { compactTitle } else { regularTitle }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isPinging {
                    Text(verbatim: "…")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                } else if let ping, ping >= 0 {
                    PingLabel(ms: ping)
                } else if ping == -1 {
                    // Пинг не прошёл — нейтральная серая чёрточка, не «ошибка»
                    Text(verbatim: "—")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }

                ClevSelectionIndicator(selected: isSelected, size: compact ? 16 : 20)
            }
            .padding(.horizontal, compact ? 11 : 12)
            .padding(.vertical, compact ? 6 : 12)
            .frame(minHeight: compact ? 38 : 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous)
                    .strokeBorder(isSelected ? Theme.yellow.opacity(0.65) : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Название хоста целиком в одну строку: длинное слегка сжимается, а не
    /// переносится и не обрезается «…».
    private func title(size: CGFloat, weight: Font.Weight) -> some View {
        Text(verbatim: displayName)
            .font(.system(size: size, weight: weight))
            .foregroundColor(Theme.textPrimary)
            .lineLimit(1)
            .allowsTightening(true)
            .minimumScaleFactor(0.6)
    }

    private func badge(size: CGFloat, horizontal: CGFloat, vertical: CGFloat) -> some View {
        Text(server.protocolType.displayName)
            .font(.system(size: size, weight: .bold))
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(Theme.surfaceLight, in: Capsule())
            .foregroundColor(Theme.yellow)
    }

    /// iOS: название, под ним бейдж протокола, ниже описание — как в эталоне.
    private var regularTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            title(size: 15, weight: .bold)
            badge(size: 11, horizontal: 5, vertical: 2)
                .padding(.top, 3)
            if let serverDescription {
                Text(serverDescription)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
    }

    /// macOS: компактно — бейдж и описание в одну строку под названием.
    private var compactTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            title(size: 13, weight: .semibold)
            HStack(spacing: 5) {
                badge(size: 9, horizontal: 4, vertical: 1)
                if let serverDescription {
                    Text(serverDescription)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Подписка

/// Текст announce из подписки: все строки, кроме последней, — крупнее и жирнее,
/// последняя — мельче, как подсказка (порт `SubscriptionAnnounceContent`).
struct AnnounceText: View {
    let text: String

    private var lines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        let all = lines
        let main = all.count > 1 ? Array(all.dropLast()) : all
        let hint = all.count > 1 ? all.last : nil

        VStack(spacing: 3) {
            ForEach(Array(main.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hint {
                Text(verbatim: hint)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Вкладка «Подписка» в настройках — одна и та же на iOS и macOS, по образцу
/// Windows / Android TV (`SubscriptionSettingsView`): карточка с названием,
/// трафиком и датой и двумя действиями; под ней «Купить в боте» и «Поддержка»,
/// на десктопе — «Выйти из приложения»; внизу логотип.
struct SubscriptionSettingsCard: View {
    let title: String?
    let info: SubscriptionUserInfo?
    let isLoading: Bool
    let supportURL: String?
    let onRefresh: () -> Void
    let onDelete: () -> Void
    /// Выход из приложения — только на десктопе: iOS не даёт приложению
    /// закрывать себя.
    var onQuit: (() -> Void)? = nil

    /// Бот из эталона (BuildConfig.TELEGRAM_BOT_URL).
    private static let botURL = URL(string: "https://t.me/ClevVPN_bot")
    private static let defaultSupportURL = URL(string: "https://t.me/clevsupport_bot")

    private var supportLink: URL? {
        if let supportURL, let url = URL(string: supportURL) { return url }
        return Self.defaultSupportURL
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    VStack(spacing: 12) {
                        titleRow
                        statsBar
                        // Все действия — одним блоком в карточке: обновить и
                        // удалить ключ, ниже бот и поддержка
                        HStack(spacing: 10) {
                            actionButton(icon: "arrow.clockwise",
                                         title: Text("Update subscription"),
                                         isLoading: isLoading,
                                         action: onRefresh)
                            actionButton(icon: "rectangle.portrait.and.arrow.right",
                                         title: Text("Remove key and sign out"),
                                         isLoading: false,
                                         action: onDelete)
                        }
                        HStack(spacing: 10) {
                            if let url = Self.botURL {
                                linkButton(Text("Buy in bot"), url: url)
                            }
                            if let url = supportLink {
                                linkButton(Text("Support"), url: url)
                            }
                        }
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )

                if let onQuit {
                    Button(action: onQuit) {
                        Text("Exit the app")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.red)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(outlinedShape)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            // Логотип — у нижнего края вкладки
            ClevLogoFull(logoHeight: 16)
                .opacity(0.5)
                .padding(.bottom, 16)
        }
    }

    /// Аватар и название подписки — по центру.
    private var titleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "person")
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Theme.textSecondary.opacity(0.65), lineWidth: 1))
            Text(verbatim: displayTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var displayTitle: String {
        if let title, !title.isEmpty, !title.lowercased().hasPrefix("base64:") { return title }
        return "CleVVpn 💛"
    }

    /// Полоса «трафик | дата окончания».
    private var statsBar: some View {
        HStack(spacing: 8) {
            Text(verbatim: trafficText)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let expires = info?.expiresAt {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text(expires, format: .dateTime.day().month(.abbreviated).year())
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                }
            }
        }
        .foregroundColor(Theme.textPrimary.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var trafficText: String {
        guard let used = info?.usedBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: used, countStyle: .binary)
    }

    /// Фон кнопок в рамке — тёмная плашка с тонкой светлой обводкой.
    private var outlinedShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.background.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.textSecondary.opacity(0.35), lineWidth: 1)
            )
    }

    private func actionButton(icon: String, title: Text, isLoading: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.yellow)
                }
                title
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(outlinedShape)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func linkButton(_ title: Text, url: URL) -> some View {
        Link(destination: url) {
            title
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(outlinedShape)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - iOS-only (сохранены при merge из mac-ios)


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

