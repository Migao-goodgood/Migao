import SwiftUI

/// Presents transient input above the current screen instead of pinning it to
/// the bottom edge. The dimmed area remains tappable for dismissal.
struct CenteredModalOverlay<Content: View>: View {
    private let onDismiss: () -> Void
    private let content: () -> Content

    init(
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onDismiss = onDismiss
        self.content = content
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            content()
                .padding(.horizontal, 18)
                .frame(maxWidth: 390)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
    }
}

/// Shared paper-like surface used by weight and body-measurement dialogs.
struct InputModalSurface<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(26)
            .frame(maxWidth: 370)
            .background(
                Color.platinumPale,
                in: RoundedRectangle(cornerRadius: 27, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .stroke(.white.opacity(0.95), lineWidth: 2)
            }
            .shadow(color: Color.platinum.opacity(0.32), radius: 28, y: 14)
    }
}

/// Consistent heading and close affordance for transient input surfaces.
struct InputModalHeader: View {
    let eyebrow: String
    let title: String
    let onDismiss: () -> Void
    var centerTitle = false

    var body: some View {
        Group {
            if centerTitle {
                ZStack {
                    Text(title)
                        .roundedFont(23, weight: .heavy)
                        .foregroundStyle(Color.warmText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .padding(.horizontal, 44)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Spacer()
                        closeButton
                    }
                }
                .frame(minHeight: 34)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        if !eyebrow.isEmpty {
                            Text(eyebrow)
                                .roundedFont(11, weight: .bold)
                                .foregroundStyle(Color.platinumDeep)
                        }
                        Text(title)
                            .roundedFont(23, weight: .heavy)
                            .foregroundStyle(Color.warmText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }

                    Spacer(minLength: 8)
                    closeButton
                }
            }
        }
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.inkSoft)
                .frame(width: 34, height: 34)
                .background(Color.platinumLight, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }
}

/// Shared primary action so every numeric record surface has the same visual
/// weight, hit area, and gradient treatment.
struct InputModalSaveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .roundedFont(15, weight: .heavy)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.jellyPink, Color.jellyBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .shadow(color: Color.platinum.opacity(0.75), radius: 0, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// A one-decimal selector shared by every weight input surface.
///
/// iPhone and iPad use two synchronized wheel columns. macOS uses native menu
/// pickers while keeping the same value model and visual grouping.
struct DecimalWeightPicker: View {
    @Binding var whole: Int
    @Binding var decimal: Int

    let wholeRange: ClosedRange<Int>
    let unit: String
    let prompt: String

    init(
        whole: Binding<Int>,
        decimal: Binding<Int>,
        wholeRange: ClosedRange<Int> = 20...300,
        unit: String = "kg",
        prompt: String = "滑动选择数值"
    ) {
        _whole = whole
        _decimal = decimal
        self.wholeRange = wholeRange
        self.unit = unit
        self.prompt = prompt
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(prompt)
                .roundedFont(13, weight: .bold)
                .foregroundStyle(Color.inkSoft)
                .frame(maxWidth: .infinity)

            pickerContainer
                .frame(maxWidth: .infinity)
                .frame(height: 174)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.platinumLight, lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.platinumLight.opacity(0.26))
                        .frame(height: 54)
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.platinum.opacity(0.9), lineWidth: 1.3)
                        }
                        .allowsHitTesting(false)
                }

            Text("精确到 0.1 \(unit)")
                .roundedFont(10, weight: .medium)
                .foregroundStyle(Color.mutedText)
        }
        .padding(.top, 22)
        .onAppear(perform: normalizeSelection)
        .onChange(of: whole) { _, _ in normalizeSelection() }
        .onChange(of: decimal) { _, _ in normalizeSelection() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(prompt)，精确到 0.1 \(unit)")
    }

    @ViewBuilder
    private var pickerContainer: some View {
        #if os(iOS)
        HStack(spacing: 0) {
            Picker("整数", selection: $whole) {
                ForEach(wholeRange, id: \.self) { value in
                    Text("\(value)")
                        .tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 116, height: 174)
            .clipped()
            .tint(Color.inkSoft)
            .accessibilityLabel("整数部分")

            Text(".")
                .roundedFont(23, weight: .heavy)
                .foregroundStyle(Color.inkSoft)
                .frame(width: 14)
                .accessibilityHidden(true)

            Picker("小数", selection: $decimal) {
                ForEach(0...maximumDecimal, id: \.self) { value in
                    Text("\(value)")
                        .tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 70, height: 174)
            .clipped()
            .tint(Color.inkSoft)
            .accessibilityLabel("小数部分")

            Text(unit)
                .roundedFont(13, weight: .heavy)
                .foregroundStyle(Color.inkSoft)
                .padding(.leading, 6)
                .frame(minWidth: 28, alignment: .leading)
        }
        #else
        HStack(spacing: 8) {
            Picker("整数", selection: $whole) {
                ForEach(wholeRange, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.menu)

            Text(".")
                .roundedFont(20, weight: .heavy)
                .foregroundStyle(Color.inkSoft)

            Picker("小数", selection: $decimal) {
                ForEach(0...maximumDecimal, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.menu)

            Text(unit)
                .roundedFont(13, weight: .heavy)
                .foregroundStyle(Color.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 55)
        #endif
    }

    private var maximumDecimal: Int {
        whole == wholeRange.upperBound ? 0 : 9
    }

    private func normalizeSelection() {
        let clampedWhole = min(wholeRange.upperBound, max(wholeRange.lowerBound, whole))
        if whole != clampedWhole {
            whole = clampedWhole
        }
        let clampedDecimal = min(maximumDecimal, max(0, decimal))
        if decimal != clampedDecimal {
            decimal = clampedDecimal
        }
    }
}

/// A compact ruler-style picker shared by the daily and goal weight surfaces.
/// The stored binding remains kilograms while the ruler follows the selected
/// display unit and keeps the same 100 g (0.1 kg) precision.
struct WeightRulerPicker: View {
    @Binding var kilograms: Double
    @Binding var unit: WeightUnit

    let valueColor: (Double) -> Color

    @State private var dragStartIndex: Int?
    @State private var dragTranslation: CGFloat = 0

    private let tickSpacing: CGFloat = 13

    init(
        kilograms: Binding<Double>,
        unit: Binding<WeightUnit>,
        valueColor: @escaping (Double) -> Color = { _ in Color.waterAccent }
    ) {
        _kilograms = kilograms
        _unit = unit
        self.valueColor = valueColor
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(unit.formattedValue(fromKilograms: displayedKilograms))
                    .roundedFont(38, weight: .heavy)
                    .foregroundStyle(activeColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(unit.rawValue)
                    .roundedFont(14, weight: .heavy)
                    .foregroundStyle(Color.inkSoft)

                Spacer(minLength: 8)
                Picker("单位", selection: $unit) {
                    ForEach(WeightUnit.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color.waterAccent)
                .frame(width: 112)
                .accessibilityLabel("体重单位")
            }

            rulerSurface
        }
        .onAppear(perform: normalize)
        .onChange(of: kilograms) { _, _ in
            if dragStartIndex == nil { normalize() }
        }
        .onChange(of: unit) { _, _ in
            dragStartIndex = nil
            dragTranslation = 0
            normalize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("体重")
        .accessibilityValue(unit.formatted(fromKilograms: displayedKilograms))
        .accessibilityAdjustableAction { direction in
            let current = unit.tickIndex(forKilograms: displayedKilograms)
            let next = direction == .increment ? current + 1 : current - 1
            kilograms = unit.kilograms(forTick: next)
        }
    }

    private var displayedKilograms: Double {
        unit.kilograms(forTick: currentIndex)
    }

    private var activeColor: Color {
        valueColor(displayedKilograms)
    }

    private var selectedIndex: Int {
        unit.tickIndex(forKilograms: kilograms)
    }

    private var anchorIndex: Int {
        dragStartIndex ?? selectedIndex
    }

    private var currentFloatIndex: CGFloat {
        let raw = CGFloat(anchorIndex) - dragTranslation / tickSpacing
        return min(CGFloat(unit.tickCount - 1), max(0, raw))
    }

    private var currentIndex: Int {
        min(unit.tickCount - 1, max(0, Int(currentFloatIndex.rounded())))
    }

    private var fractionalOffset: CGFloat {
        currentFloatIndex - CGFloat(currentIndex)
    }

    private var visibleIndices: [Int] {
        let lower = max(0, currentIndex - 34)
        let upper = min(unit.tickCount - 1, currentIndex + 34)
        return Array(lower...upper)
    }

    private var rulerSurface: some View {
        GeometryReader { proxy in
            let center = proxy.size.width / 2
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.74))
                Rectangle()
                    .fill(Color.platinum)
                    .frame(height: 1)
                    .position(x: center, y: 55)

                ForEach(visibleIndices, id: \.self) { index in
                    let distance = CGFloat(index - currentIndex) + fractionalOffset
                    let x = center + distance * tickSpacing
                    WeightRulerTick(
                        isMajor: index.isMultiple(of: 10),
                        isMedium: index.isMultiple(of: 5),
                        label: index.isMultiple(of: 10) ? unit.rulerLabel(forTick: index) : nil
                    )
                    .position(x: x, y: 65)
                    .allowsHitTesting(false)
                }

                WeightRulerPointer()
                    .fill(activeColor)
                    .frame(width: 24, height: 22)
                    .position(x: center, y: 17)
                Rectangle()
                    .fill(activeColor)
                    .frame(width: 2, height: 42)
                    .position(x: center, y: 38)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(rulerDragGesture)
        }
        .frame(height: 126)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.platinumLight, lineWidth: 1)
        }
    }

    private var rulerDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStartIndex == nil {
                    dragStartIndex = selectedIndex
                }
                dragTranslation = gesture.translation.width
            }
            .onEnded { _ in
                let next = currentIndex
                withAnimation(.easeOut(duration: 0.16)) {
                    kilograms = unit.kilograms(forTick: next)
                }
                dragStartIndex = nil
                dragTranslation = 0
            }
    }

    private func normalize() {
        let normalized = unit.kilograms(forTick: unit.tickIndex(forKilograms: kilograms))
        if abs(normalized - kilograms) > 0.0001 {
            kilograms = normalized
        }
    }
}

private struct WeightRulerTick: View {
    let isMajor: Bool
    let isMedium: Bool
    let label: String?

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(isMajor ? Color.inkSoft : Color.platinum)
                .frame(width: isMajor ? 2 : 1, height: isMajor ? 40 : (isMedium ? 29 : 20))
            if let label {
                Text(label)
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(Color.inkSoft)
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                Color.clear.frame(height: 16)
            }
        }
        .frame(width: 60, height: 78, alignment: .top)
    }
}

private struct WeightRulerPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A wheel-based date selector. iPhone/iPad use a sliding wheel; macOS keeps
/// the same dates in a native menu to match platform conventions.
struct DateWheelPicker: View {
    @Binding var date: Date
    let range: ClosedRange<Date>

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = .current
        return value
    }

    private var days: [Date] {
        let start = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound)
        let count = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        return (0...count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        Picker("记录日期", selection: normalizedBinding) {
            ForEach(days, id: \.self) { day in
                Text(label(for: day)).tag(day)
            }
        }
        .labelsHidden()
        #if os(iOS)
        .pickerStyle(.wheel)
        .frame(height: 104)
        #else
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, minHeight: 42)
        #endif
        .tint(Color.inkSoft)
        .clipped()
        .accessibilityLabel("记录日期")
        .accessibilityValue(label(for: calendar.startOfDay(for: date)))
        .onAppear(perform: normalizeDate)
    }

    private var normalizedBinding: Binding<Date> {
        Binding(
            get: { calendar.startOfDay(for: date) },
            set: { date = calendar.startOfDay(for: $0) }
        )
    }

    private func label(for day: Date) -> String {
        if calendar.isDateInToday(day) { return "今天 · \(shortDate(day))" }
        if calendar.isDateInYesterday(day) { return "昨天 · \(shortDate(day))" }
        return shortDate(day)
    }

    private func shortDate(_ day: Date) -> String {
        Self.dateFormatter.string(from: day)
    }

    private func normalizeDate() {
        let start = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound)
        let normalized = min(end, max(start, calendar.startOfDay(for: date)))
        if normalized != date { date = normalized }
    }
}

/// Shared framed presentation for date wheels used by daily measurements.
struct DateWheelSurface: View {
    @Binding var date: Date
    let range: ClosedRange<Date>

    init(date: Binding<Date>, range: ClosedRange<Date> = WeightDateRange.allowed) {
        _date = date
        self.range = range
    }

    var body: some View {
        DateWheelPicker(date: $date, range: range)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.platinumLight, lineWidth: 1)
            }
    }
}

enum WeightDateRange {
    static var allowed: ClosedRange<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now)
        let earliest = calendar.date(byAdding: .day, value: -730, to: today) ?? today
        return earliest...today
    }
}

/// Semantic alias for non-weight measurements that use the same one-decimal
/// wheel interaction (for example body circumferences in centimetres).
typealias DecimalNumberPicker = DecimalWeightPicker

enum DecimalWeightValue {
    static func components(
        from value: Double,
        wholeRange: ClosedRange<Int> = 20...300
    ) -> (whole: Int, decimal: Int) {
        guard value.isFinite else {
            return (wholeRange.lowerBound, 0)
        }
        let lower = wholeRange.lowerBound * 10
        let upper = wholeRange.upperBound * 10
        let boundedValue = min(Double(wholeRange.upperBound), max(Double(wholeRange.lowerBound), value))
        let tenths = Int((boundedValue * 10).rounded())
        let clamped = min(upper, max(lower, tenths))
        return (clamped / 10, clamped % 10)
    }

    static func value(whole: Int, decimal: Int) -> Double {
        Double(whole) + Double(decimal) / 10
    }
}
