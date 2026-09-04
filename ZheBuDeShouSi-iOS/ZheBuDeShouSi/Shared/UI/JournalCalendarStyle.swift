import SwiftUI

/// Shared visual and layout language for the weight and diet month grids.
/// Feature cells supply their own data content and fill tone, while geometry
/// and interaction emphasis remain consistent across both journals.
enum JournalCalendarStyle {
    static let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]
    static let cardRadius: CGFloat = 24
    static let cardHorizontalPadding: CGFloat = 16
    static let cardVerticalPadding: CGFloat = 18
    static let cellRadius: CGFloat = 14
    static let cellHeight: CGFloat = 62
    static let columnSpacing: CGFloat = 7
    static let rowSpacing: CGFloat = 8
    static let weekdaySpacing: CGFloat = 14
    static let selectionAccent = Color.jellyPink
    static let emptyCellFill = Color.platinumPale.opacity(0.28)
    static let emptyCellBorder = Color.platinumLight.opacity(0.72)

    static func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = .current
        value.firstWeekday = 2 // Monday first for both journals.
        return value
    }

    static func columns() -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: columnSpacing), count: 7)
    }

    static func monthGrid(for month: Date, calendar inputCalendar: Calendar) -> [Date?] {
        var calendar = inputCalendar
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var dates = Array<Date?>(repeating: nil, count: leading)
        dates += (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        while dates.count % 7 != 0 { dates.append(nil) }
        return dates
    }
}

extension View {
    /// Shared outer surface used by the two month calendars.
    func journalCalendarSurface() -> some View {
        self
            .background(Color.white, in: RoundedRectangle(cornerRadius: JournalCalendarStyle.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: JournalCalendarStyle.cardRadius, style: .continuous)
                    .stroke(Color.platinumLight, lineWidth: 1)
            }
            .shadow(color: Color.platinum.opacity(0.18), radius: 14, y: 7)
    }
}
