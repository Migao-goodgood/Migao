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
}

enum DietNumberText {
    static func kcal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }
}

struct DietPageHeader: View {
    let totalCalories: Int
    let recordedDays: Int
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("饮食日记")
                        .roundedFont(29, weight: .heavy)
                        .foregroundStyle(DietPalette.ink)
                    Text("把每一餐，留成一页温柔的记录")
                        .roundedFont(12, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                }
                Spacer(minLength: 12)
                DietAddMealButton(action: onAdd)
            }

            HStack(spacing: 0) {
                DietHeaderMetric(value: "\(totalCalories)", label: "本月 kcal", tint: DietPalette.pinkDeep)
                Rectangle()
                    .fill(DietPalette.rule)
                    .frame(width: 1, height: 28)
                DietHeaderMetric(value: "\(recordedDays)", label: "记录天数", tint: DietPalette.lilac)
                Spacer(minLength: 0)
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
        Button(action: action) {
            AddMediaActionLabel(
                systemName: "fork.knife",
                foregroundColor: DietPalette.pinkDeep,
                surfaceColor: DietPalette.pinkWash,
                badgeColor: DietPalette.pink,
                borderColor: DietPalette.paper
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("上传饮食照片")
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

    private let calendar = Calendar.current
    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(symbol == "日" ? DietPalette.pinkDeep : DietPalette.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 7) {
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
                            .aspectRatio(0.82, contentMode: .fit)
                    }
                }
            }
        }
        .padding(14)
        .dietSurface(radius: 20)
    }

    private var monthGrid: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        // Calendar weekday is Sunday=1. Convert to a Monday-first grid.
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        var dates = Array<Date?>(repeating: nil, count: leading)
        dates += (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        while dates.count % 7 != 0 { dates.append(nil) }
        return dates
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

    private let calendar = Calendar.current

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .roundedFont(14, weight: isToday || isSelected ? .heavy : .semibold)
                    .monospacedDigit()
                    .foregroundStyle(dayColor)
                if let summary, summary.totalCaloriesKcal > 0 {
                    Text(DietNumberText.kcal(summary.totalCaloriesKcal))
                        .roundedFont(8, weight: .bold)
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
            .frame(minHeight: 49)
            .background(cellBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? DietPalette.pink : .clear, lineWidth: isSelected ? 1.5 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var dayColor: Color {
        if isSelected { return DietPalette.pinkDeep }
        if isToday { return DietPalette.ink }
        return DietPalette.ink.opacity(0.82)
    }

    private var cellBackground: Color {
        guard let summary, summary.totalCaloriesKcal > 0 else {
            return isToday ? DietPalette.pinkWash.opacity(0.55) : Color.clear
        }
        let ratio = min(max(Double(summary.totalCaloriesKcal) / 2_200, 0.14), 1)
        return DietPalette.pinkWash.opacity(0.28 + ratio * 0.62)
    }

    private var accessibilityText: String {
        let day = "\(calendar.component(.day, from: date))日"
        guard let summary, summary.totalCaloriesKcal > 0 else { return "\(day)，暂无饮食记录" }
        return "\(day)，摄入 \(DietNumberText.kcal(summary.totalCaloriesKcal)) 千卡"
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
                Text("\(DietNumberText.kcal(summary.totalCaloriesKcal)) kcal")
                    .roundedFont(11, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(DietPalette.pinkDeep)
            }
            Text(summary.mealCount == 0 ? "待补充" : "\(summary.mealCount) 餐 · \(summary.imageCount) 张照片")
                .roundedFont(10, weight: .medium)
                .foregroundStyle(DietPalette.muted)
        }
        .padding(10)
        .dietSurface(radius: 18)
    }
}

struct DietMealPhotoCollage: View {
    let meals: [MealRecord]
    var compact = false

    private var photoItems: [(data: Data, calories: Double?)] {
        meals.flatMap { meal in
            meal.images.compactMap { image in
                guard let data = image.imageData else { return nil }
                return (data: data, calories: meal.calculatedCaloriesKcal)
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

private struct DietPhotoTile: View {
    let item: (data: Data, calories: Double?)
    let compact: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DietImageThumbnail(data: item.data, contentMode: .fill)
            if let calories = item.calories, calories > 0 {
                Text("\(DietNumberText.kcal(calories)) kcal")
                    .roundedFont(compact ? 8 : 10, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, compact ? 5 : 7)
                    .frame(height: compact ? 19 : 23)
                    .background(Color.black.opacity(0.48), in: Capsule())
                    .padding(compact ? 5 : 8)
            }
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
    let onRemove: ((MealRecord) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(meals) { meal in
                DietMealRow(meal: meal, onRemove: onRemove.map { action in { action(meal) } })
            }
        }
    }
}

private struct DietMealRow: View {
    let meal: MealRecord
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 11) {
            DietImageThumbnail(data: meal.images.first?.imageData, contentMode: .fill)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meal.mealType.title)
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(DietPalette.pinkDeep)
                    Text(meal.title.isEmpty ? "待命名的一餐" : meal.title)
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
                Text(DietNumberText.kcal(meal.calculatedCaloriesKcal ?? 0))
                    .roundedFont(16, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(DietPalette.pinkDeep)
                Text("kcal")
                    .roundedFont(9, weight: .medium)
                    .foregroundStyle(DietPalette.muted)
            }
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DietPalette.muted)
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除这餐")
            }
        }
        .padding(10)
        .background(DietPalette.paper.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DietKcalSummary: View {
    let totalCalories: Double
    let mealCount: Int
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
                Text(isToday ? "今天的摄入" : "当天的摄入")
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(DietPalette.muted)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(DietNumberText.kcal(totalCalories))
                        .roundedFont(28, weight: .heavy)
                        .monospacedDigit()
                        .foregroundStyle(DietPalette.ink)
                    Text("kcal")
                        .roundedFont(11, weight: .bold)
                        .foregroundStyle(DietPalette.pinkDeep)
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
                    DietKcalSummary(totalCalories: summary.totalCaloriesKcal, mealCount: summary.mealCount, isToday: calendar.isDateInToday(date))

                    DietDayUploadAction(
                        title: meals.isEmpty ? "添加饮食照片" : "继续添加照片",
                        subtitle: meals.isEmpty ? "一次可选多张，之后还能继续追加" : "可再次选择，拼成今天的餐桌",
                        onUpload: onUpload
                    )

                    if !meals.isEmpty {
                        DietMealPhotoCollage(meals: meals)
                            .frame(height: 192)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        DietMealList(meals: meals, onRemove: onRemove)
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

struct DietRecognitionReviewCard: View {
    @Binding var draft: DietPhotoAnalysisDraft
    let imageData: [Data]
    let isLoading: Bool
    let errorMessage: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(DietPalette.lilacWash).frame(width: 35, height: 35)
                    Image(systemName: isLoading ? "sparkles" : "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DietPalette.lilac)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? "正在整理这餐" : "识别结果待确认")
                        .roundedFont(14, weight: .heavy)
                        .foregroundStyle(DietPalette.ink)
                    Text(isLoading ? "照片只在当前设备处理，不会自动保存原图" : (draft.sourceLabel.isEmpty ? "请核对名称和热量" : draft.sourceLabel))
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(DietPalette.muted)
                }
                Spacer(minLength: 4)
                if isLoading { ProgressView().controlSize(.small).tint(DietPalette.lilac) }
            }

            if !imageData.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(imageData.prefix(4).enumerated()), id: \.offset) { _, data in
                        DietImageThumbnail(data: data, contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if imageData.count > 4 {
                        Text("+\(imageData.count - 4)")
                            .roundedFont(11, weight: .bold)
                            .foregroundStyle(DietPalette.muted)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("这餐叫什么")
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(DietPalette.muted)
                    TextField("例如：番茄鸡蛋面", text: $draft.title)
                        .roundedFont(13, weight: .medium)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(height: 39)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(DietPalette.rule, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("热量")
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(DietPalette.muted)
                    HStack(spacing: 3) {
                        TextField("0", value: caloriesBinding, format: .number)
                            .roundedFont(16, weight: .heavy)
                            .monospacedDigit()
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 58)
                        Text("kcal")
                            .roundedFont(10, weight: .bold)
                            .foregroundStyle(DietPalette.pinkDeep)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 39)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(DietPalette.rule, lineWidth: 1))
                }
            }

            if !draft.foods.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(draft.foods) { food in
                            Text(food.name)
                                .roundedFont(10, weight: .bold)
                                .foregroundStyle(DietPalette.ink)
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(DietPalette.mintWash, in: Capsule())
                        }
                    }
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(DietPalette.pinkDeep)
            }

            HStack(spacing: 9) {
                Button("稍后确认", action: onCancel)
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(DietPalette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(DietPalette.lilacWash, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Button("确认加入", action: onConfirm)
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(DietPalette.pink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .disabled(isLoading || !draft.isReadyForConfirmation)
                    .opacity(isLoading || !draft.isReadyForConfirmation ? 0.45 : 1)
            }
        }
        .padding(15)
        .dietSurface(radius: 20)
    }

    private var caloriesBinding: Binding<Int> {
        Binding(
            get: { draft.caloriesKcal ?? 0 },
            set: { draft.caloriesKcal = max(0, $0) }
        )
    }
}
