import SwiftUI

/// A deterministic, presentation-ready summary for one local calendar day.
/// The persisted WeightRecord.change value is intentionally not used here:
/// imported or back-filled records may make that field stale.
struct WeightDaySummary: Identifiable {
    let day: Date
    let representative: WeightRecord
    let recordCount: Int
    let previousRecordedWeight: Double?

    var id: Date { day }

    var deltaFromPreviousRecordedDay: Double? {
        guard let previousRecordedWeight else { return nil }
        return representative.weight - previousRecordedWeight
    }
}

enum WeightCalendarService {
    static func summaries(
        records: [WeightRecord],
        calendar inputCalendar: Calendar = .current
    ) -> [WeightDaySummary] {
        var calendar = inputCalendar
        calendar.firstWeekday = 1 // Sunday first, matching the calendar UI.

        let grouped = Dictionary(grouping: records) {
            calendar.startOfDay(for: $0.date)
        }
        let orderedDays = grouped.keys.sorted()
        var summaries: [WeightDaySummary] = []
        summaries.reserveCapacity(orderedDays.count)

        for day in orderedDays {
            guard let dayRecords = grouped[day], !dayRecords.isEmpty else { continue }
            let representative = dayRecords.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }.last!
            summaries.append(
                WeightDaySummary(
                    day: day,
                    representative: representative,
                    recordCount: dayRecords.count,
                    previousRecordedWeight: summaries.last?.representative.weight
                )
            )
        }

        return Array(summaries.reversed())
    }
}

enum WeightCalendarColorMapper {
    struct Style {
        let tone: Color
        let fillOpacity: Double
        let borderOpacity: Double
        let textOpacity: Double
    }

    static func style(
        weight: Double,
        startWeight: Double,
        goalWeight: Double,
        delta: Double?
    ) -> Style {
        let lowerReference = min(startWeight, goalWeight)
        let upperReference = max(startWeight, goalWeight)
        let referenceSpan = max(1, upperReference - lowerReference)
        let basePosition = clamp((weight - lowerReference) / referenceSpan)
        let dailyShift = clamp((delta ?? 0) / 1.5, lower: -1, upper: 1) * 0.18
        let position = clamp(basePosition + dailyShift)
        let overflow = clamp((weight - upperReference) / max(3, referenceSpan * 0.45))

        let blue = RGB(red: 112, green: 200, blue: 218)
        let pink = RGB(red: 245, green: 141, blue: 174)
        let deepPink = RGB(red: 217, green: 79, blue: 112)
        let gradientTone = interpolate(from: blue, to: pink, amount: position)
        let tone = interpolate(from: gradientTone, to: deepPink, amount: overflow)
        let riseMagnitude = max(0, clamp((delta ?? 0) / 1.5))

        return Style(
            tone: tone.color,
            fillOpacity: 0.10 + position * 0.24 + overflow * 0.08 + riseMagnitude * 0.05,
            borderOpacity: 0.18 + position * 0.30 + overflow * 0.12,
            textOpacity: 0.76 + position * 0.18 + overflow * 0.06
        )
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red / 255, green: green / 255, blue: blue / 255)
        }
    }

    private static func interpolate(from start: RGB, to end: RGB, amount: Double) -> RGB {
        let value = clamp(amount)
        return RGB(
            red: start.red + (end.red - start.red) * value,
            green: start.green + (end.green - start.green) * value,
            blue: start.blue + (end.blue - start.blue) * value
        )
    }

    private static func clamp(_ value: Double, lower: Double = 0, upper: Double = 1) -> Double {
        min(upper, max(lower, value))
    }
}

/// Shared compact title matching the hierarchy of the InBody latest summary.
/// Both home weight modules use this component so typography stays aligned.
struct WeightModuleTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .roundedFont(19, weight: .heavy)
            .foregroundStyle(Color.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

struct WeightCalendarView: View {
    @ObservedObject var state: AppState
    let onRecord: () -> Void

    @State private var displayedMonth: Date

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = .current
        value.firstWeekday = 1
        return value
    }

    init(state: AppState, onRecord: @escaping () -> Void) {
        self.state = state
        self.onRecord = onRecord
        let seed = state.records.max(by: { $0.date < $1.date })?.date ?? .now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        _displayedMonth = State(initialValue: calendar.date(
            from: calendar.dateComponents([.year, .month], from: seed)
        ) ?? seed)
    }

    private var summaries: [WeightDaySummary] {
        WeightCalendarService.summaries(records: state.records, calendar: calendar)
    }

    private var summariesByDay: [Date: WeightDaySummary] {
        Dictionary(uniqueKeysWithValues: summaries.map { ($0.day, $0) })
    }

    private var monthStart: Date {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: displayedMonth)
        ) ?? displayedMonth
    }

    private var monthTitle: String {
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    private var monthRecordCount: Int {
        let monthComponents = calendar.dateComponents([.year, .month], from: monthStart)
        return summaries.filter { day in
            let components = calendar.dateComponents([.year, .month], from: day.day)
            return components.year == monthComponents.year && components.month == monthComponents.month
        }.count
    }

    private var canMoveForward: Bool {
        let current = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ) ?? .now
        return monthStart < current
    }

    private var calendarDates: [Date?] {
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? (1..<31)
        let leading = calendar.component(.weekday, from: monthStart) - 1
        let totalDays = dayRange.count
        return (0..<42).map { index in
            let dayIndex = index - leading
            guard dayIndex >= 0, dayIndex < totalDays else { return nil }
            return calendar.date(byAdding: .day, value: dayIndex, to: monthStart)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                WeightModuleTitle(title: "体重日历")
                Spacer(minLength: 8)
                header
            }
            monthNavigation
                .padding(.top, 14)
            weekdayHeader
                .padding(.top, 18)
            calendarGrid
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.platinumLight, lineWidth: 1)
        }
        .shadow(color: Color.platinum.opacity(0.18), radius: 14, y: 7)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer()
            Text("本月 \(monthRecordCount) 天")
                .roundedFont(11, weight: .medium)
                .foregroundStyle(Color.platinumDeep)

            Button(action: onRecord) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .heavy))
                    Text("记录")
                        .roundedFont(10, weight: .bold)
                }
                .foregroundStyle(Color.inkSoft)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.jellyMint.opacity(0.24), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("记录体重")
        }
    }

    private var monthNavigation: some View {
        HStack(spacing: 12) {
            calendarArrow("chevron.left", label: "上个月") {
                moveMonth(-1)
            }
            Spacer()
            Text(monthTitle)
                .roundedFont(16, weight: .bold)
                .foregroundStyle(Color.ink)
            Spacer()
            calendarArrow("chevron.right", label: "下个月") {
                moveMonth(1)
            }
            .opacity(canMoveForward ? 1 : 0.32)
            .disabled(!canMoveForward)
        }
        .padding(.top, 18)
    }

    private func calendarArrow(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.inkSoft)
                .frame(width: 30, height: 30)
                .background(Color.platinumPale, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: calendarColumns, spacing: 0) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                Text(day)
                    .roundedFont(10, weight: .bold)
                    .foregroundStyle(Color.platinumDeep)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: calendarColumns, spacing: 7) {
            ForEach(Array(calendarDates.enumerated()), id: \.offset) { _, date in
                if let date {
                    WeightCalendarDayCell(
                        date: date,
                        summary: summariesByDay[calendar.startOfDay(for: date)],
                        startWeight: state.startWeight ?? WeightUnit.minimumKilograms,
                        goalWeight: state.hasConfiguredGoal
                            ? state.goalWeight
                            : (state.startWeight ?? WeightUnit.minimumKilograms),
                        unit: state.weightUnit,
                        calendar: calendar
                    )
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 7), count: 7)
    }

    private func moveMonth(_ offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: monthStart) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = next
        }
    }
}

private struct WeightCalendarDayCell: View {
    let date: Date
    let summary: WeightDaySummary?
    let startWeight: Double
    let goalWeight: Double
    let unit: WeightUnit
    let calendar: Calendar

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    private var tone: Color {
        summary == nil ? Color.platinumDeep : style.tone
    }

    private var style: WeightCalendarColorMapper.Style {
        WeightCalendarColorMapper.style(
            weight: summary?.representative.weight ?? goalWeight,
            startWeight: startWeight,
            goalWeight: goalWeight,
            delta: summary?.deltaFromPreviousRecordedDay
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .roundedFont(10, weight: .bold)
                .foregroundStyle(summary == nil ? Color.platinumDeep : Color.inkSoft)

            if let summary {
                Text(unit.formattedValue(fromKilograms: summary.representative.weight))
                    .roundedFont(17, weight: .heavy)
                    .foregroundStyle(tone.opacity(style.textOpacity))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .roundedFont(17, weight: .heavy)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(
            summary == nil ? Color.platinumPale.opacity(0.35) : tone.opacity(style.fillOpacity),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    isToday ? tone : tone.opacity(summary == nil ? 0.10 : style.borderOpacity),
                    lineWidth: isToday ? 1.5 : 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let day = "\(calendar.component(.day, from: date))日"
        guard let summary else { return "\(day)，没有体重记录" }
        let weight = unit.formatted(fromKilograms: summary.representative.weight)
        guard let delta = summary.deltaFromPreviousRecordedDay, abs(delta) >= 0.05 else {
            return "\(day)，\(weight)"
        }
        return "\(day)，\(weight)，较上次\(delta > 0 ? "上升" : "下降")\(unit.formatted(fromKilograms: abs(delta)))"
    }
}
