import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum DietDateText {
    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    static let dayDetail: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let recordedDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}

enum DietNumberText {
    static func kcal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    static func kcal(_ value: Double, estimated: Bool) -> String {
        (estimated ? "约 " : "") + kcal(value)
    }
}

struct DietPageHeader: View {
    let totalCalories: Int
    let recordedDays: Int
    var knownCaloriesMealCount: Int = 0
    var missingCaloriesMealCount: Int = 0
    var hasEstimatedCalories: Bool = false
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JournalPageLayout.sectionSpacing) {
            JournalPageHeader(title: "饮食日记", titleColor: Color.ink) {
                DietAddMealButton(action: onAdd)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    DietHeaderMetric(
                        value: knownCaloriesMealCount > 0 ? DietNumberText.kcal(Double(totalCalories), estimated: hasEstimatedCalories) : (recordedDays > 0 ? "待补充" : "—"),
                        label: knownCaloriesMealCount > 0 ? "本月已记录 kcal" : "本月热量",
                        tint: DietPalette.pinkDeep
                    )
                    Rectangle()
                        .fill(DietPalette.rule)
                        .frame(width: 1, height: 28)
                    DietHeaderMetric(value: "\(recordedDays)", label: "记录天数", tint: DietPalette.lilac)
                    Spacer(minLength: 0)
                }
                if missingCaloriesMealCount > 0 {
                    Text("\(missingCaloriesMealCount) 餐热量待补充")
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(DietPalette.lilacWash.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct DietAddMealButton: View {
    let action: () -> Void

    var body: some View {
        JournalAddActionButton(
            systemName: "fork.knife",
            foregroundColor: DietPalette.pinkDeep,
            surfaceColor: DietPalette.pinkWash,
            badgeColor: DietPalette.pink,
            borderColor: DietPalette.paper,
            accessibilityLabel: "上传饮食照片",
            action: action
        )
    }
}

private struct DietHeaderMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(value)
                .roundedFont(20, weight: .heavy)
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .roundedFont(10, weight: .medium)
                .foregroundStyle(DietPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DietMonthToolbar: View {
    let month: Date
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPreviousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(DietPalette.ink)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(DietPalette.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一个月")

            Text(DietDateText.month.string(from: month))
                .roundedFont(17, weight: .heavy)
                .foregroundStyle(DietPalette.ink)
                .frame(maxWidth: .infinity)

            Button(action: onNextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(DietPalette.ink)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(DietPalette.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一个月")

            Button(action: onToday) {
                Text("今天")
                    .roundedFont(11, weight: .bold)
                    .foregroundStyle(DietPalette.pinkDeep)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(DietPalette.pinkWash, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct DietDisplayModePicker: View {
    @Binding var selection: DietDisplayMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DietDisplayMode.allCases) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = mode }
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                        .labelStyle(.titleAndIcon)
                        .roundedFont(12, weight: selection == mode ? .bold : .medium)
                        .foregroundStyle(selection == mode ? DietPalette.ink : DietPalette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selection == mode ? Color.white : Color.clear, in: Capsule())
                        .shadow(color: selection == mode ? DietPalette.pink.opacity(0.12) : .clear, radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(DietPalette.pinkWash.opacity(0.68), in: Capsule())
    }
}

struct DietMonthCalendar: View {
    let month: Date
    let summaries: [DietDaySummary]
    @Binding var selectedDate: Date
    let onSelectDate: (Date) -> Void

    private let calendar = JournalCalendarStyle.calendar()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(JournalCalendarStyle.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(symbol == "日" ? JournalCalendarStyle.selectionAccent : Color.platinumDeep)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: JournalCalendarStyle.columns(), spacing: JournalCalendarStyle.rowSpacing) {
                ForEach(Array(monthGrid.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DietCalendarCell(
                            date: date,
                            summary: summary(for: date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            onTap: { onSelectDate(date) }
                        )
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: JournalCalendarStyle.cellHeight)
                    }
                }
            }
        }
        .padding(.horizontal, JournalCalendarStyle.cardHorizontalPadding)
        .padding(.vertical, JournalCalendarStyle.cardVerticalPadding)
        .journalCalendarSurface()
    }

    private var monthGrid: [Date?] {
        JournalCalendarStyle.monthGrid(for: month, calendar: calendar)
    }

    private func summary(for date: Date) -> DietDaySummary? {
        summaries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

private struct DietCalendarCell: View {
    let date: Date
    let summary: DietDaySummary?
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    private let calendar = JournalCalendarStyle.calendar()

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .roundedFont(14, weight: isToday || isSelected ? .heavy : .semibold)
                    .monospacedDigit()
                    .foregroundStyle(dayColor)
                if let summary, summary.mealCount > 0 {
                    Text(summary.knownCaloriesMealCount > 0 ? DietNumberText.kcal(summary.totalCaloriesKcal, estimated: summary.hasEstimatedCalories) : "待补充")
                        .roundedFont(10, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(DietPalette.pinkDeep.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                } else {
                    Circle()
                        .fill(isToday ? DietPalette.pink.opacity(0.48) : DietPalette.rule.opacity(0.72))
                        .frame(width: 3.5, height: 3.5)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: JournalCalendarStyle.cellHeight)
            .background(cellBackground, in: RoundedRectangle(cornerRadius: JournalCalendarStyle.cellRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: JournalCalendarStyle.cellRadius, style: .continuous)
                    .stroke(isSelected ? JournalCalendarStyle.selectionAccent : JournalCalendarStyle.emptyCellBorder, lineWidth: isSelected ? 1.6 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var dayColor: Color {
        if isSelected || isToday { return JournalCalendarStyle.selectionAccent }
        return Color.inkSoft
    }

    private var cellBackground: Color {
        guard let summary, summary.mealCount > 0 else {
            return isToday ? DietPalette.pinkWash.opacity(0.55) : JournalCalendarStyle.emptyCellFill
        }
        guard summary.knownCaloriesMealCount > 0 else { return DietPalette.lilacWash.opacity(0.6) }
        let ratio = min(max(Double(summary.totalCaloriesKcal) / 2_200, 0.14), 1)
        return DietPalette.pinkWash.opacity(0.22 + ratio * 0.48)
    }

    private var accessibilityText: String {
        let day = "\(calendar.component(.day, from: date))日"
        guard let summary, summary.mealCount > 0 else { return "\(day)，暂无饮食记录" }
        guard summary.knownCaloriesMealCount > 0 else { return "\(day)，已记录 \(summary.mealCount) 餐，热量待补充" }
        let missing = summary.missingCaloriesMealCount > 0 ? "，\(summary.missingCaloriesMealCount) 餐热量待补充" : ""
        return "\(day)，已记录 \(DietNumberText.kcal(summary.totalCaloriesKcal, estimated: summary.hasEstimatedCalories)) 千卡\(missing)"
    }
}

struct DietMosaicGrid: View {
    let summaries: [DietDaySummary]
    let onSelectDate: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        if summaries.isEmpty {
            DietEmptyState(
                icon: "photo.on.rectangle.angled",
                title: "这个月还没有饮食拼贴",
                message: "上传第一餐，让这个月慢慢长出自己的颜色。"
            )
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(summaries.sorted(by: { $0.date > $1.date })) { summary in
                    Button { onSelectDate(summary.date) } label: {
                        DietMosaicDayCard(summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DietMosaicDayCard: View {
    let summary: DietDaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            DietMealPhotoCollage(meals: summary.records, compact: true)
                .frame(height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(DietDateText.short.string(from: summary.date))
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(DietPalette.ink)
                Spacer(minLength: 3)
                Text(summary.knownCaloriesMealCount > 0 ? "\(DietNumberText.kcal(summary.totalCaloriesKcal, estimated: summary.hasEstimatedCalories)) kcal" : "待补充")
                    .roundedFont(11, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(DietPalette.pinkDeep)
            }
            Text(summary.mealCount == 0 ? "待补充" : "\(summary.mealCount) 餐 · \(summary.imageCount) 张照片")
                .roundedFont(10, weight: .medium)
                .foregroundStyle(DietPalette.muted)
            if summary.missingCaloriesMealCount > 0, summary.knownCaloriesMealCount > 0 {
                Text("已记录 · \(summary.missingCaloriesMealCount) 餐热量待补充")
                    .roundedFont(9, weight: .medium)
                    .foregroundStyle(DietPalette.muted)
            }
        }
        .padding(10)
        .dietSurface(radius: 18)
    }
}

struct DietMealPhotoCollage: View {
    let meals: [MealRecord]
    var compact = false

    private var photoItems: [DietMealPhotoItem] {
        meals.flatMap { meal in
            meal.images.compactMap { image in
                guard let data = image.imageData else { return nil }
                return DietMealPhotoItem(
                    data: data,
                    calories: meal.calculatedCaloriesKcal,
                    isEstimated: meal.isCalorieEstimate,
                    sharesMealTotal: meal.images.count > 1
                )
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = compact ? 4 : 7
            let items = Array(photoItems.prefix(compact ? 4 : 6))
            if items.isEmpty {
                ZStack {
                    LinearGradient(
                        colors: [DietPalette.pinkWash, DietPalette.lilacWash],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: compact ? 24 : 31, weight: .light))
                        .foregroundStyle(DietPalette.pink.opacity(0.72))
                }
            } else if items.count == 1 {
                DietPhotoTile(item: items[0], compact: compact)
            } else if items.count == 2 {
                HStack(spacing: spacing) {
                    DietPhotoTile(item: items[0], compact: compact)
                    DietPhotoTile(item: items[1], compact: compact)
                }
                .clipped()
            } else if items.count == 3 {
                HStack(spacing: spacing) {
                    DietPhotoTile(item: items[0], compact: compact)
                        .frame(width: proxy.size.width * 0.54)
                    VStack(spacing: spacing) {
                        ForEach(Array(items.dropFirst().enumerated()), id: \.offset) { _, item in
                            DietPhotoTile(item: item, compact: compact)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .clipped()
            } else {
                let columnCount = items.count >= 5 ? 3 : 2
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount),
                    spacing: spacing
                ) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        DietPhotoTile(item: item, compact: compact)
                            .frame(height: max(1, (proxy.size.height - spacing) / 2))
                    }
                }
                .clipped()
            }
        }
        .background(DietPalette.pinkWash)
        .clipped()
    }
}

private struct DietMealPhotoItem {
    let data: Data
    let calories: Double?
    let isEstimated: Bool
    let sharesMealTotal: Bool

    var calorieLabel: String {
        let prefix = sharesMealTotal ? "本餐" : ""
        guard let calories else { return prefix + "待补充" }
        return prefix + DietNumberText.kcal(calories, estimated: isEstimated) + " kcal"
    }
}

private struct DietPhotoTile: View {
    let item: DietMealPhotoItem
    let compact: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DietImageThumbnail(data: item.data, contentMode: .fill)
            Text(item.calorieLabel)
                .roundedFont(compact ? 8 : 10, weight: .bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 5 : 7)
                .frame(height: compact ? 19 : 23)
                .background(Color.black.opacity(0.48), in: Capsule())
                .padding(compact ? 5 : 8)
        }
        .clipped()
    }
}

struct DietImageThumbnail: View {
    let data: Data?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            #if os(iOS)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
            #elseif os(macOS)
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [DietPalette.pinkWash, DietPalette.lilacWash], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DietPalette.muted.opacity(0.7))
        }
    }
}

struct DietMealList: View {
    let meals: [MealRecord]
    let onEdit: (MealRecord) -> Void
    let onRemove: (MealRecord) -> Void

    @State private var openMealID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(meals) { meal in
                DietMealRow(
                    meal: meal,
                    openMealID: $openMealID,
                    onEdit: { onEdit(meal) },
                    onRemove: { onRemove(meal) }
                )
            }
        }
        .onChange(of: meals.map(\.id)) { _, mealIDs in
            if let openMealID, !mealIDs.contains(openMealID) {
                self.openMealID = nil
            }
        }
    }
}

private struct DietMealRow: View {
    let meal: MealRecord
    @Binding var openMealID: UUID?
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        DietSwipeActionRow(
            id: meal.id,
            openItemID: $openMealID,
            accessibilityLabel: mealAccessibilityLabel,
            accessibilityValue: mealAccessibilityValue,
            onEdit: onEdit,
            onRemove: onRemove
        ) {
            rowContent
        }
    }

    private var mealAccessibilityLabel: String {
        meal.title.isEmpty ? meal.mealType.title : "\(meal.mealType.title)，\(meal.title)"
    }

    private var mealAccessibilityValue: String {
        guard let calories = meal.calculatedCaloriesKcal else { return "未填写热量" }
        return "\(DietNumberText.kcal(calories, estimated: meal.isCalorieEstimate)) 千卡"
    }

    private var rowContent: some View {
        HStack(spacing: 11) {
            DietImageThumbnail(data: meal.images.first?.imageData, contentMode: .fill)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meal.mealType.title)
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(DietPalette.pinkDeep)
                    Text(meal.title.isEmpty ? (meal.images.isEmpty ? "饮食记录" : "饮食照片") : meal.title)
                        .roundedFont(14, weight: .bold)
                        .foregroundStyle(DietPalette.ink)
                        .lineLimit(1)
                }
                if !meal.foods.isEmpty {
                    Text(meal.foods.prefix(3).map(\.name).joined(separator: " · "))
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                        .lineLimit(1)
                } else if !meal.note.isEmpty {
                    Text(meal.note)
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(meal.calculatedCaloriesKcal.map { DietNumberText.kcal($0, estimated: meal.isCalorieEstimate) } ?? "待补充")
                    .roundedFont(meal.calculatedCaloriesKcal == nil ? 12 : 16, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(DietPalette.pinkDeep)
                Text(meal.calculatedCaloriesKcal == nil ? "热量" : "kcal")
                    .roundedFont(9, weight: .medium)
                    .foregroundStyle(DietPalette.muted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(DietPalette.paper.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DietSwipeActionRow<Content: View>: View {
    let id: UUID
    @Binding var openItemID: UUID?
    let accessibilityLabel: String
    let accessibilityValue: String
    let onEdit: () -> Void
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragState = SwipeDragState()

    private let actionWidth: CGFloat = 120
    private let rowHeight: CGFloat = 74

    private var isOpen: Bool { openItemID == id }
    private var baseOffset: CGFloat { isOpen ? actionWidth : 0 }
    private var contentOffset: CGFloat {
        min(actionWidth, max(0, baseOffset + dragState.translation))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            actionButtons
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)

            foregroundContent
        }
        .frame(height: rowHeight)
        .background(DietPalette.lilacWash.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button(action: performEdit) {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive, action: performRemove) {
                Label("删除", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("点按编辑，或向右轻扫显示编辑和删除")
        .accessibilityAction { performEdit() }
        .accessibilityAction(named: "编辑这条饮食记录", performEdit)
        .accessibilityAction(named: "删除这条饮食记录", performRemove)
    }

    private var foregroundContent: some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .offset(x: contentOffset)
            .onTapGesture(perform: tappedContent)
            .simultaneousGesture(swipeGesture)
    }

    private func tappedContent() {
        if isOpen { close() } else { performEdit() }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            Button(action: performEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DietPalette.lilac)
                    .frame(width: actionWidth / 2, height: rowHeight)
                    .background(DietPalette.lilacWash)
            }
            .buttonStyle(.plain)
            .help("编辑")
            .accessibilityLabel("编辑这条饮食记录")

            Button(role: .destructive, action: performRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DietPalette.pinkDeep)
                    .frame(width: actionWidth / 2, height: rowHeight)
                    .background(DietPalette.pinkWash)
            }
            .buttonStyle(.plain)
            .help("删除")
            .accessibilityLabel("删除这条饮食记录")
        }
        .frame(width: actionWidth, height: rowHeight)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragState) { value, state, _ in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                if state.direction == .undecided, hypot(horizontal, vertical) >= 8 {
                    state.direction = horizontal > vertical * 1.2 ? .horizontal : .vertical
                }
                guard state.direction == .horizontal else { return }
                state.translation = value.translation.width
            }
            .onChanged { _ in
                guard dragState.direction == .horizontal,
                      openItemID != nil,
                      openItemID != id else { return }
                withAnimation(settleAnimation) { openItemID = nil }
            }
            .onEnded { value in
                guard dragState.direction == .horizontal else { return }
                let projectedOffset = baseOffset + value.predictedEndTranslation.width
                let shouldOpen = projectedOffset > actionWidth * 0.42
                withAnimation(settleAnimation) {
                    openItemID = shouldOpen ? id : nil
                }
            }
    }

    private var settleAnimation: Animation? {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.28, dampingFraction: 0.86)
    }

    private struct SwipeDragState {
        enum Direction {
            case undecided
            case horizontal
            case vertical
        }

        var direction = Direction.undecided
        var translation: CGFloat = 0
    }

    private func close() {
        withAnimation(settleAnimation) { openItemID = nil }
    }

    private func performEdit() {
        close()
        onEdit()
    }

    private func performRemove() {
        close()
        onRemove()
    }
}

struct DietKcalSummary: View {
    let totalCalories: Double
    let mealCount: Int
    var knownCaloriesMealCount: Int = 0
    var missingCaloriesMealCount: Int = 0
    var hasEstimatedCalories: Bool = false
    let isToday: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                Circle()
                    .fill(DietPalette.pinkWash)
                    .frame(width: 48, height: 48)
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DietPalette.pinkDeep)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(isToday ? "今日已记录" : "当天已记录")
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(DietPalette.muted)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(knownCaloriesMealCount > 0 ? DietNumberText.kcal(totalCalories, estimated: hasEstimatedCalories) : (mealCount > 0 ? "待补充" : "暂无记录"))
                        .roundedFont(knownCaloriesMealCount > 0 ? 28 : 22, weight: .heavy)
                        .monospacedDigit()
                        .foregroundStyle(DietPalette.ink)
                    if knownCaloriesMealCount > 0 {
                        Text("kcal")
                            .roundedFont(11, weight: .bold)
                            .foregroundStyle(DietPalette.pinkDeep)
                    }
                }
                if missingCaloriesMealCount > 0 {
                    Text("\(missingCaloriesMealCount) 餐热量待补充")
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                }
            }
            Spacer(minLength: 4)
            Text("\(mealCount) 餐")
                .roundedFont(11, weight: .bold)
                .foregroundStyle(DietPalette.lilac)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(DietPalette.lilacWash, in: Capsule())
        }
        .padding(13)
        .background(DietPalette.pinkWash.opacity(0.56), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct DietEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(DietPalette.pink.opacity(0.76))
            Text(title)
                .roundedFont(15, weight: .heavy)
                .foregroundStyle(DietPalette.ink)
            Text(message)
                .roundedFont(11, weight: .medium)
                .foregroundStyle(DietPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .dietSurface(radius: 20)
    }
}

struct DietCenteredOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            content()
                .padding(.horizontal, 18)
                .frame(maxWidth: 560, maxHeight: 690)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .zIndex(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct DietDayDetailModal: View {
    let date: Date
    let meals: [MealRecord]
    let summary: DietDaySummary
    let onDismiss: () -> Void
    let onUpload: () -> Void
    let onEdit: (MealRecord) -> Void
    let onRemove: (MealRecord) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(DietDateText.dayDetail.string(from: date))
                    .roundedFont(21, weight: .heavy)
                    .foregroundStyle(DietPalette.ink)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DietPalette.muted)
                        .frame(width: 32, height: 32)
                        .background(DietPalette.lilacWash, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    DietKcalSummary(
                        totalCalories: summary.totalCaloriesKcal,
                        mealCount: summary.mealCount,
                        knownCaloriesMealCount: summary.knownCaloriesMealCount,
                        missingCaloriesMealCount: summary.missingCaloriesMealCount,
                        hasEstimatedCalories: summary.hasEstimatedCalories,
                        isToday: calendar.isDateInToday(date)
                    )

                    DietDayUploadAction(
                        title: meals.isEmpty ? "添加饮食照片" : "继续添加照片",
                        subtitle: meals.isEmpty ? "一次可选多张，之后还能继续追加" : "可再次选择，拼成今天的餐桌",
                        onUpload: onUpload
                    )

                    if !meals.isEmpty {
                        DietMealPhotoCollage(meals: meals)
                            .frame(height: 192)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        DietMealList(meals: meals, onEdit: onEdit, onRemove: onRemove)
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .padding(18)
        .background(DietPalette.paper, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1.5)
        }
        .shadow(color: DietPalette.ink.opacity(0.16), radius: 28, y: 14)
    }
}

struct DietMealEditModal: View {
    @State private var draft: DietMealEditDraft
    @State private var errorMessage = ""

    let onSave: (DietMealEditDraft) -> Bool
    let onDismiss: () -> Void

    init(
        meal: MealRecord,
        onSave: @escaping (DietMealEditDraft) -> Bool,
        onDismiss: @escaping () -> Void
    ) {
        _draft = State(initialValue: DietMealEditDraft(meal: meal))
        self.onSave = onSave
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text("编辑饮食记录")
                    .roundedFont(21, weight: .heavy)
                    .foregroundStyle(DietPalette.ink)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DietPalette.muted)
                        .frame(width: 32, height: 32)
                        .background(DietPalette.lilacWash, in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭")
                .accessibilityLabel("关闭编辑")
            }
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    DietRecordDatePicker(date: $draft.recordedAt)

                    editField(title: "餐次") {
                        Picker("餐次", selection: $draft.mealType) {
                            ForEach(DietMealType.allCases) { mealType in
                                Text(mealType.title).tag(mealType)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    editField(title: "名称（选填）") {
                        TextField("可留空", text: $draft.title)
                            .roundedFont(13, weight: .medium)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DietPalette.rule, lineWidth: 1)
                            }
                    }

                    editField(title: "热量（选填）") {
                        HStack(spacing: 6) {
                            TextField("待补充", text: $draft.caloriesText)
                                .roundedFont(18, weight: .heavy)
                                .monospacedDigit()
                                .textFieldStyle(.plain)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("kcal")
                                .roundedFont(11, weight: .bold)
                                .foregroundStyle(DietPalette.pinkDeep)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(draft.caloriesInputIsValid ? DietPalette.rule : DietPalette.pinkDeep, lineWidth: 1)
                        }
                    }

                    if !draft.caloriesInputIsValid {
                        Label("请输入 0 至 20000，最多保留一位小数", systemImage: "exclamationmark.circle.fill")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(DietPalette.pinkDeep)
                    } else if draft.caloriesKcal == nil {
                        Text("留空后会标为待补充，不会计作 0 kcal。")
                            .roundedFont(10, weight: .medium)
                            .foregroundStyle(DietPalette.muted)
                    }

                    if !DietEntryInputRules.supportedDateRange.contains(draft.recordedAt) {
                        Label("请选择 2000 年 1 月 1 日至今天之间的日期", systemImage: "calendar.badge.exclamationmark")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(DietPalette.pinkDeep)
                    }

                    if !errorMessage.isEmpty {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(DietPalette.pinkDeep)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 430)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif

            HStack(spacing: 9) {
                Button("取消", action: onDismiss)
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(DietPalette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DietPalette.lilacWash, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .buttonStyle(.plain)

                Button("保存", action: save)
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DietPalette.pink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(!draft.canSave)
                    .opacity(draft.canSave ? 1 : 0.45)
            }
            .padding(.top, 18)
        }
        .padding(18)
        .background(DietPalette.paper, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1.5)
        }
        .shadow(color: DietPalette.ink.opacity(0.16), radius: 28, y: 14)
        .onChange(of: draft.caloriesText) { _, _ in errorMessage = "" }
    }

    private func editField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .roundedFont(10, weight: .bold)
                .foregroundStyle(DietPalette.muted)
            content()
        }
    }

    private func save() {
        guard draft.canSave else {
            errorMessage = draft.caloriesInputIsValid ? "请保留至少一项记录内容" : "请检查热量格式"
            return
        }
        guard onSave(draft) else {
            errorMessage = "这条记录暂时无法保存，请稍后重试。"
            return
        }
    }
}

private struct DietDayUploadAction: View {
    let title: String
    let subtitle: String
    let onUpload: () -> Void

    var body: some View {
        Button(action: onUpload) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DietPalette.pinkWash)
                        .frame(width: 46, height: 46)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.92), lineWidth: 1.2)
                        }

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DietPalette.pinkDeep)

                    ZStack {
                        Circle()
                            .fill(DietPalette.pink)
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(DietPalette.paper, lineWidth: 2)
                    }
                    .offset(x: 16, y: 16)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .roundedFont(14, weight: .heavy)
                        .foregroundStyle(DietPalette.ink)
                    Text(subtitle)
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DietPalette.muted)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 70)
            .background(
                LinearGradient(
                    colors: [DietPalette.pinkWash.opacity(0.72), DietPalette.lilacWash.opacity(0.72)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DietPalette.rule, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("支持多次选择照片")
    }
}

/// Pending captures remain separate from confirmed meals and their totals.
struct DietDraftShelf: View {
    let drafts: [DietCaptureDraft]
    let onResume: (DietCaptureDraft) -> Void
    let onRemove: (DietCaptureDraft) -> Void

    var body: some View {
        if !drafts.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Text("待确认")
                        .roundedFont(14, weight: .bold)
                        .foregroundStyle(DietPalette.ink)
                    Text("\(drafts.count)")
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(DietPalette.lilac)
                    Spacer()
                    Text("尚未计入日历")
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(drafts.sorted(by: { $0.updatedAt > $1.updatedAt })) { capture in
                            HStack(spacing: 0) {
                                Button { onResume(capture) } label: {
                                    HStack(spacing: 9) {
                                        DietImageThumbnail(data: capture.images.first?.imageData)
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(DietDateText.short.string(from: capture.date)) · \(capture.analysis.mealType.title)")
                                                .roundedFont(12, weight: .bold)
                                                .foregroundStyle(DietPalette.ink)
                                            Text("\(capture.images.count) 张照片 · 继续确认")
                                                .roundedFont(10, weight: .medium)
                                                .foregroundStyle(DietPalette.muted)
                                        }
                                    }
                                    .padding(.vertical, 9)
                                    .padding(.leading, 9)
                                    .padding(.trailing, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("继续确认 \(DietDateText.dayDetail.string(from: capture.date)) 的\(capture.analysis.mealType.title)，\(capture.images.count) 张照片")

                                Button(role: .destructive) { onRemove(capture) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(DietPalette.muted)
                                        .frame(width: 44, height: 54)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("删除这份待确认草稿")
                            }
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(DietPalette.rule, lineWidth: 1)
                            }
                        }
                    }
                }
            }
            .padding(13)
            .background(DietPalette.lilacWash.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct DietRecordDatePicker: View {
    @Binding var date: Date
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("记录日期", systemImage: "calendar")
                        .foregroundStyle(DietPalette.muted)
                    Spacer(minLength: 8)
                    Text(DietDateText.recordedDate.string(from: date))
                        .foregroundStyle(DietPalette.ink)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DietPalette.pinkDeep)
                }
                .roundedFont(12, weight: .semibold)
                .frame(minHeight: 43)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("展开后滑动选择日期")

            if isExpanded {
                DatePicker("记录日期", selection: $date, in: DietEntryInputRules.supportedDateRange, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 136)
                    .clipped()
            }
            #else
            DatePicker("记录日期", selection: $date, in: DietEntryInputRules.supportedDateRange, displayedComponents: .date)
                .datePickerStyle(.compact)
                .roundedFont(12, weight: .semibold)
                .foregroundStyle(DietPalette.ink)
                .frame(minHeight: 43)
            #endif
        }
        .tint(DietPalette.pinkDeep)
        .padding(.horizontal, 11)
        .background(DietPalette.lilacWash.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DietRecognitionReviewCard: View {
    @Binding var draft: DietPhotoAnalysisDraft
    @Binding var recordedAt: Date
    let imageData: [Data]
    let isLoading: Bool
    let errorMessage: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onDiscard: () -> Void
    let onRetry: (() -> Void)?

    @State private var caloriesText: String
    @State private var showsManualCalories = false
    @State private var showsName = false

    init(
        draft: Binding<DietPhotoAnalysisDraft>,
        recordedAt: Binding<Date>,
        imageData: [Data],
        isLoading: Bool,
        errorMessage: String?,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDiscard: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        _draft = draft
        _recordedAt = recordedAt
        self.imageData = imageData
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onDiscard = onDiscard
        self.onRetry = onRetry
        _caloriesText = State(initialValue: draft.wrappedValue.caloriesKcal.map(String.init) ?? "")
    }

    private var caloriesInputIsValid: Bool {
        DietEntryInputRules.normalizedCalories(caloriesText).isEmpty
            || DietEntryInputRules.calories(caloriesText, wholeNumbersOnly: true) != nil
    }

    private var canSave: Bool {
        !imageData.isEmpty && caloriesInputIsValid && DietEntryInputRules.supportedDateRange.contains(recordedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("记录饮食")
                        .roundedFont(21, weight: .heavy)
                        .foregroundStyle(DietPalette.ink)
                    Text("本地文字识别，照片也可先保存")
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                }
                Spacer(minLength: 5)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DietPalette.muted)
                        .frame(width: 34, height: 34)
                        .background(DietPalette.lilacWash, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!caloriesInputIsValid)
                .accessibilityLabel(imageData.isEmpty ? "取消读取照片" : "保存草稿并关闭")
            }
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 13) {
                    if !imageData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(Array(imageData.enumerated()), id: \.offset) { index, data in
                                    DietImageThumbnail(data: data)
                                        .frame(width: 78, height: 78)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        .accessibilityLabel("第 \(index + 1) 张饮食照片")
                                }
                            }
                        }
                    }

                    calorieReview

                    recordDetails
                        .disabled(isLoading)

                    if !caloriesInputIsValid {
                        Label("请输入 0 至 20000 的整数，或清空后稍后补充", systemImage: "exclamationmark.circle.fill")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(DietPalette.pinkDeep)
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(DietPalette.pinkDeep)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 440)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif

            HStack(spacing: 9) {
                Button(imageData.isEmpty ? "取消" : "稍后确认", action: onCancel)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(DietPalette.lilac)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DietPalette.lilacWash, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(!caloriesInputIsValid)
                    .opacity(caloriesInputIsValid ? 1 : 0.45)

                Button(isLoading && !imageData.isEmpty ? "保存照片" : "保存", action: onConfirm)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DietPalette.pink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
            }
            .padding(.top, 14)

            if !imageData.isEmpty {
                Button("删除这份草稿", role: .destructive, action: onDiscard)
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(DietPalette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .buttonStyle(.plain)
                    .padding(.top, 3)
            }
        }
        .padding(18)
        .dietSurface(radius: 27)
        .onChange(of: draft.caloriesKcal) { _, calories in
            // The analyzer may finish after this card has appeared. User text
            // remains untouched while it is invalid and awaits correction.
            guard isLoading || caloriesInputIsValid else { return }
            caloriesText = calories.map(String.init) ?? ""
        }
        .onChange(of: isLoading) { _, loading in
            if loading {
                showsManualCalories = false
            }
        }
    }

    private var calorieReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Label("本餐热量", systemImage: "text.viewfinder")
                    .roundedFont(11, weight: .bold)
                    .foregroundStyle(DietPalette.pinkDeep)
                Spacer(minLength: 6)
                if let onRetry, !imageData.isEmpty, !isLoading {
                    Button {
                        caloriesText = draft.caloriesKcal.map(String.init) ?? ""
                        onRetry()
                    } label: {
                        Label("重新读取文字", systemImage: "arrow.clockwise")
                            .roundedFont(10, weight: .semibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DietPalette.lilac)
                    .frame(minHeight: 28)
                }
            }

            calorieHero

            Text(sourceDescription)
                .roundedFont(11, weight: .medium)
                .foregroundStyle(DietPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !isLoading {
                DisclosureGroup(isExpanded: $showsManualCalories) {
                    manualCaloriesField
                        .padding(.top, 7)
                } label: {
                    Text(draft.caloriesKcal == nil ? "手动补充热量（选填）" : "手动调整热量")
                        .roundedFont(11, weight: .semibold)
                        .foregroundStyle(DietPalette.pinkDeep)
                }
                .tint(DietPalette.pinkDeep)
            }
        }
        .padding(14)
        .background(DietPalette.pinkWash.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var calorieHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isLoading {
                ProgressView().controlSize(.small).tint(DietPalette.lilac)
                Text(imageData.isEmpty ? "读取照片中" : "读取文字中")
                    .roundedFont(25, weight: .heavy)
                    .foregroundStyle(DietPalette.ink)
            } else if let calories = draft.caloriesKcal {
                Text("\(calories)")
                    .roundedFont(38, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(DietPalette.ink)
                Text("kcal")
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(DietPalette.pinkDeep)
                if imageData.count > 1 {
                    Text("请核对本餐用量")
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                }
            } else {
                Text("待补充")
                    .roundedFont(28, weight: .heavy)
                    .foregroundStyle(DietPalette.ink)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceDescription: String {
        if isLoading {
            return imageData.isEmpty ? "照片读取完成后会开始本地文字识别。" : "正在读取照片中的热量文字，也可以先保存照片。"
        }
        let source = draft.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.isEmpty { return source }
        return draft.caloriesKcal == nil
            ? "未读到热量文字，照片可以先保存，再手动补充。"
            : "请核对 kcal/kJ 单位，以及每份或每 100g 的标注，再填写实际摄入热量。"
    }

    private var recordDetails: some View {
        VStack(alignment: .leading, spacing: 13) {
            DietRecordDatePicker(date: $recordedAt)

            reviewField(title: "餐次") {
                Picker("餐次", selection: $draft.mealType) {
                    ForEach(DietMealType.allCases) { mealType in
                        Text(mealType.title).tag(mealType)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            DisclosureGroup(isExpanded: $showsName) {
                TextField("可留空", text: $draft.title)
                    .roundedFont(13, weight: .medium)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 11)
                    .frame(height: 42)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DietPalette.rule, lineWidth: 1))
                    .padding(.top, 7)
            } label: {
                Text("名称（选填）")
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(DietPalette.muted)
            }
            .tint(DietPalette.muted)
        }
    }

    private var manualCaloriesField: some View {
        HStack(spacing: 6) {
            TextField("留空可稍后补充", text: caloriesBinding)
                .roundedFont(20, weight: .heavy)
                .monospacedDigit()
                .textFieldStyle(.plain)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text("kcal")
                .roundedFont(11, weight: .bold)
                .foregroundStyle(DietPalette.pinkDeep)
        }
        .padding(.horizontal, 11)
        .frame(height: 44)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(caloriesInputIsValid ? DietPalette.rule : DietPalette.pinkDeep, lineWidth: 1)
        }
    }

    private var caloriesBinding: Binding<String> {
        Binding(
            get: { caloriesText },
            set: { text in
                caloriesText = text
                // Invalid input must not silently preserve the previous kcal.
                var adjusted = draft
                adjusted.caloriesKcal = DietEntryInputRules.calories(text, wholeNumbersOnly: true).map(Int.init)
                adjusted.estimatedCaloriesKcal = nil
                adjusted.portionMultiplier = nil
                adjusted.sourceLabel = adjusted.caloriesKcal == nil ? "热量待补充，可重新读取照片中的文字。" : "手动填写热量"
                draft = adjusted
            }
        )
    }

    private func reviewField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .roundedFont(10, weight: .bold)
                .foregroundStyle(DietPalette.muted)
            content()
        }
    }
}
