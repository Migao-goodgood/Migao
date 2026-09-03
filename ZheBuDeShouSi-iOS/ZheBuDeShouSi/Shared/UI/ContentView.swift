import SwiftUI
import PhotosUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var healthSync: HealthSyncCoordinator
    @EnvironmentObject private var bodyTrend: BodyTrendStore
    @EnvironmentObject private var diet: DietStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tab: AppTab = .home
    @State private var recordType: RecordType?
    @State private var isEditingGoal = false
    @State private var isTrendModalPresented = false
    @State private var isAboutPresented = false
    private let inBodyReminderPlanner = InBodyMeasurementReminderPlanner()
    private let inBodyReminderScheduler = AnyInBodyMeasurementReminderScheduler.live

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.platinumPale
                .ignoresSafeArea()

            Group {
                switch tab {
                case .home:
                    HomeView(
                        state: state,
                        diet: diet,
                        onRecord: present,
                        onEditGoal: presentGoalEditor,
                        onShowTrend: presentTrend,
                        onShowDiet: presentDiet
                    )
                case .diet:
                    DietView(store: diet)
                case .trend:
                    BodyTrendView(
                        store: bodyTrend,
                        weightUnit: state.weightUnit,
                        onMeasurementScheduleChanged: synchronizeInBodyReminder
                    )
                case .mine:
                    ProfileView(
                        state: state,
                        health: health,
                        healthSync: healthSync,
                        diet: diet,
                        onShowAbout: presentAbout
                    )
                }
            }
            .frame(maxWidth: usesWideLayout ? 720 : .infinity, maxHeight: .infinity, alignment: .top)

            BottomNav(selected: $tab)

            if let recordType {
                CenteredModalOverlay(onDismiss: dismissRecord) {
                    RecordModal(type: recordType, state: state, onDismiss: dismissRecord)
                }
                    .transition(.opacity)
                    .zIndex(2)
            }

            if isEditingGoal {
                CenteredModalOverlay(onDismiss: dismissGoalEditor) {
                    GoalWeightModal(state: state, onDismiss: dismissGoalEditor)
                }
                    .transition(.opacity)
                    .zIndex(3)
            }

            if isTrendModalPresented {
                CenteredModalOverlay(onDismiss: dismissTrend) {
                    WeightTrendModal(state: state, onDismiss: dismissTrend)
                }
                    .transition(.opacity)
                    .zIndex(4)
            }

            if isAboutPresented {
                CenteredModalOverlay(onDismiss: dismissAbout) {
                    AboutQuoteModal(onDismiss: dismissAbout)
                }
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: recordType != nil)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isEditingGoal)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isTrendModalPresented)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isAboutPresented)
    }

    private var usesWideLayout: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    private func present(_ type: RecordType) {
        withAnimation { recordType = type }
    }

    private func dismissRecord() {
        withAnimation { recordType = nil }
    }

    private func presentGoalEditor() {
        withAnimation { isEditingGoal = true }
    }

    private func dismissGoalEditor() {
        withAnimation { isEditingGoal = false }
    }

    private func presentTrend() {
        withAnimation { isTrendModalPresented = true }
    }

    private func presentDiet() {
        withAnimation { tab = .diet }
    }

    private func dismissTrend() {
        withAnimation { isTrendModalPresented = false }
    }

    private func presentAbout() {
        withAnimation { isAboutPresented = true }
    }

    private func dismissAbout() {
        withAnimation { isAboutPresented = false }
    }

    private func synchronizeInBodyReminder(
        _ schedule: InBodyMeasurementSchedule,
        lastMeasurementDate: Date?
    ) async -> Bool {
        if !schedule.isEnabled {
            await inBodyReminderScheduler.cancel(
                identifier: InBodyMeasurementReminderRequest.defaultIdentifier
            )
            return true
        }

        do {
            guard try await inBodyReminderScheduler.requestAuthorization() else {
                return false
            }
            // Before the first report there is no meaningful cadence anchor.
            // Saving that first report schedules the notification immediately.
            guard lastMeasurementDate != nil else {
                await inBodyReminderScheduler.cancel(
                    identifier: InBodyMeasurementReminderRequest.defaultIdentifier
                )
                return true
            }
            guard let request = inBodyReminderPlanner.request(
                    for: schedule,
                    lastMeasurementDate: lastMeasurementDate
                  ) else {
                return true
            }
            try await inBodyReminderScheduler.schedule(request)
            return true
        } catch {
            return false
        }
    }

}

private struct HomeView: View {
    @ObservedObject var state: AppState
    @ObservedObject var diet: DietStore
    let onRecord: (RecordType) -> Void
    let onEditGoal: () -> Void
    let onShowTrend: () -> Void
    let onShowDiet: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                HomePlanCard(state: state, onEditGoal: onEditGoal)
                HomeDietEntry(store: diet, onOpen: onShowDiet)
                HomeTrendAndHistory(
                    state: state,
                    onShowTrend: onShowTrend,
                    onRecord: { onRecord(.weight) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 122)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.platinumPale.ignoresSafeArea())
    }
}

private struct HomeDietEntry: View {
    @ObservedObject var store: DietStore
    let onOpen: () -> Void

    private var summary: DietDaySummary { store.summary(for: .now) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(DietPalette.pinkWash)
                        .frame(width: 42, height: 42)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DietPalette.pinkDeep)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("今日饮食")
                        .roundedFont(14, weight: .bold)
                        .foregroundStyle(DietPalette.ink)
                    if summary.mealCount == 0 {
                        Text("还没有记录，去留下一餐吧")
                            .roundedFont(10, weight: .medium)
                            .foregroundStyle(DietPalette.muted)
                    } else {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(DietNumberText.kcal(summary.totalCaloriesKcal))
                                .roundedFont(19, weight: .heavy)
                                .monospacedDigit()
                                .foregroundStyle(DietPalette.pinkDeep)
                            Text("kcal · \(summary.mealCount) 餐")
                                .roundedFont(10, weight: .medium)
                                .foregroundStyle(DietPalette.muted)
                        }
                    }
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DietPalette.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DietPalette.lilacWash.opacity(0.58), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(DietPalette.rule, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("今日饮食")
        .accessibilityValue(summary.mealCount == 0 ? "暂无记录" : "摄入 \(DietNumberText.kcal(summary.totalCaloriesKcal)) 千卡，共 \(summary.mealCount) 餐")
    }
}

private struct HomePlanCard: View {
    @ObservedObject var state: AppState
    let onEditGoal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("轻盈进度")
                        .roundedFont(26, weight: .heavy)
                        .foregroundStyle(Color.ink)
                    if let seasonalNote {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("今日 · \(seasonalNote.name)")
                                .roundedFont(11, weight: .bold)
                                .foregroundStyle(Color.waterAccent)
                            Text(seasonalNote.text)
                                .roundedFont(11, weight: .medium)
                                .foregroundStyle(Color.platinumDeep)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 1)
                    }
                }
            }

            HomeProgressRail(
                startWeight: state.startWeight,
                currentWeight: state.weight,
                endWeight: state.goalWeight,
                currentTone: state.weightTone(state.weight),
                unit: state.weightUnit,
                onEditGoal: onEditGoal
            )
                .padding(.top, 28)

        }
        .padding(.horizontal, 20)
        .padding(.top, 19)
        .padding(.bottom, 18)
        .background(
            LinearGradient(colors: [Color.white, Color.platinumPale], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 27, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(Color.platinumLight, lineWidth: 1))
        .shadow(color: Color.platinum.opacity(0.28), radius: 18, y: 9)
    }

    private var seasonalNote: SolarTermGreeting? {
        SolarTermService.greeting(on: .now)
    }

}

private struct HomeProgressRail: View {
    let startWeight: Double
    let currentWeight: Double
    let endWeight: Double
    let currentTone: Color
    let unit: WeightUnit
    let onEditGoal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                progressValue(startWeight, color: Color.platinumDeep, alignment: .bottomLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("起始体重")
                    .accessibilityValue(unit.formatted(fromKilograms: startWeight))
                progressValue(currentWeight, color: currentTone, alignment: .bottom, isEmphasized: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("当前体重")
                    .accessibilityValue(unit.formatted(fromKilograms: currentWeight))
                Button(action: onEditGoal) {
                    progressValue(endWeight, color: Color.ink, alignment: .bottomTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottomTrailing)
                .contentShape(Rectangle())
                .accessibilityLabel("编辑目标体重")
                .accessibilityValue(unit.formatted(fromKilograms: endWeight))
                .accessibilityHint("双击打开目标体重选择器")
            }
            .padding(.horizontal, 1)

            GeometryReader { proxy in
                let trackY = proxy.size.height / 2
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [Color.jellyPink, Color.jellyBlue], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.78), lineWidth: 1)
                        }

                    railTick(color: Color.platinumDeep.opacity(0.48))
                        .position(x: 1, y: trackY)
                    railTick(color: currentTone)
                        .position(x: proxy.size.width / 2, y: trackY)
                    railTick(color: Color.platinumDeep.opacity(0.48))
                        .position(x: max(1, proxy.size.width - 1), y: trackY)
                }
            }
            .frame(height: 24)
            .padding(.top, 4)

            segmentAnnotations
                .padding(.top, 1)
        }
        .frame(minHeight: 88)
    }

    private func progressValue(
        _ value: Double,
        color: Color,
        alignment: Alignment,
        isEmphasized: Bool = false
    ) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text(unit.formattedValue(fromKilograms: value))
                .roundedFont(isEmphasized ? 19 : 13, weight: isEmphasized ? .heavy : .bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(unit.rawValue)
                .roundedFont(isEmphasized ? 11 : 9, weight: .bold)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: alignment)
    }

    private func railTick(color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 2, height: 22)
    }

    private var segmentAnnotations: some View {
        HStack(spacing: 0) {
            SegmentWeightAnnotation(
                title: "已减",
                amount: abs(currentWeight - startWeight),
                color: Color.mintGreen,
                unit: unit,
                isDashed: false
            )
            .frame(maxWidth: .infinity)

            SegmentWeightAnnotation(
                title: "距离目标体重还差",
                amount: abs(endWeight - currentWeight),
                color: Color.platinumDeep,
                unit: unit,
                isDashed: true
            )
            .frame(maxWidth: .infinity)
        }
        .frame(height: 39)
    }
}

private struct SegmentWeightAnnotation: View {
    let title: String
    let amount: Double
    let color: Color
    let unit: WeightUnit
    let isDashed: Bool

    var body: some View {
        VStack(spacing: 3) {
            MathUnderbrace()
                .stroke(
                    color.opacity(isDashed ? 0.50 : 0.58),
                    style: isDashed
                        ? StrokeStyle(lineWidth: 1.15, lineCap: .butt, lineJoin: .round, dash: [3.5, 3])
                        : StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
                )
                .padding(.horizontal, 6)
                .frame(height: 9)

            Text(title)
                .roundedFont(9, weight: .medium)
                .foregroundStyle(Color.platinumDeep)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(unit.formatted(fromKilograms: amount))
                .roundedFont(10, weight: .bold)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)\(unit.formatted(fromKilograms: amount))")
    }
}

/// A restrained mathematical-style underbrace used for the two progress
/// segments. The flatter shoulders keep the annotation calm at small widths.
private struct MathUnderbrace: Shape {
    func path(in rect: CGRect) -> Path {
        guard rect.width > 12 else { return Path() }

        let height = rect.height
        let hook = min(8, rect.width * 0.08)
        let neck = min(10, rect.width * 0.10)
        let shoulder = rect.minY + height * 0.48
        let dip = rect.maxY - 1
        let mid = rect.midX

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 1))
        path.addCurve(
            to: CGPoint(x: rect.minX + hook, y: shoulder),
            control1: CGPoint(x: rect.minX, y: rect.minY + height * 0.18),
            control2: CGPoint(x: rect.minX + hook * 0.30, y: shoulder)
        )
        path.addLine(to: CGPoint(x: mid - neck, y: shoulder))
        path.addQuadCurve(
            to: CGPoint(x: mid, y: dip),
            control: CGPoint(x: mid - neck * 0.42, y: dip)
        )
        path.addQuadCurve(
            to: CGPoint(x: mid + neck, y: shoulder),
            control: CGPoint(x: mid + neck * 0.42, y: dip)
        )
        path.addLine(to: CGPoint(x: rect.maxX - hook, y: shoulder))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + 1),
            control1: CGPoint(x: rect.maxX - hook * 0.30, y: shoulder),
            control2: CGPoint(x: rect.maxX, y: rect.minY + height * 0.18)
        )
        return path
    }
}

private struct HomeTrendAndHistory: View {
    @ObservedObject var state: AppState
    let onShowTrend: () -> Void
    let onRecord: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Button(action: onShowTrend) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 10) {
                        WeightModuleTitle(title: "体重趋势")
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("近 30 天")
                            .roundedFont(12, weight: .bold)
                            .foregroundStyle(Color.inkSoft)
                        Spacer(minLength: 8)
                        Text(trendDeltaText)
                            .roundedFont(11, weight: .bold)
                            .foregroundStyle(trendDeltaColor)
                    }
                    WeightTrendChart(records: state.records, goal: state.goalWeight)
                        .frame(maxWidth: .infinity)
                        .frame(height: 82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看体重趋势")
            .accessibilityValue(trendDeltaText)
            .padding(.vertical, 17)
            .padding(.horizontal, 17)
            .frame(maxWidth: 620)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(Color.platinumLight, lineWidth: 1))
            .shadow(color: Color.platinum.opacity(0.2), radius: 15, y: 7)

            WeightCalendarView(state: state, onRecord: onRecord)
                .frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity)
    }

    private var latestWeight: Double? {
        state.records.max(by: { $0.date < $1.date })?.weight
    }

    private var earliestWeight: Double? {
        state.records.min(by: { $0.date < $1.date })?.weight
    }

    private var trendDelta: Double? {
        guard let latestWeight, let earliestWeight else { return nil }
        return latestWeight - earliestWeight
    }

    private var trendDeltaText: String {
        guard let trendDelta else { return "等待记录" }
        if abs(trendDelta) < 0.05 { return "保持稳定" }
        return "\(trendDelta < 0 ? "下降 " : "上升 ")\(state.weightUnit.formatted(fromKilograms: abs(trendDelta)))"
    }

    private var trendDeltaColor: Color {
        guard let trendDelta else { return Color.platinumDeep }
        return trendDelta <= 0 ? Color(hex: "58A993") : Color(hex: "D66B83")
    }

}

private struct AppHeader: View {
    let eyebrow: String
    let title: String
    let mascot: MascotKind
    let showsMascot: Bool
    let actionIcon: String?
    let actionLabel: String?
    let onAction: (() -> Void)?

    init(
        eyebrow: String,
        title: String,
        mascot: MascotKind,
        showsMascot: Bool = true,
        actionIcon: String? = nil,
        actionLabel: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.mascot = mascot
        self.showsMascot = showsMascot
        self.actionIcon = actionIcon
        self.actionLabel = actionLabel
        self.onAction = onAction
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow).roundedFont(11, weight: .bold).tracking(1.2).foregroundStyle(Color.waterAccent)
                Text(title).roundedFont(27, weight: .heavy).foregroundStyle(Color.warmText).lineLimit(2)
            }
            Spacer(minLength: 8)
            if let actionIcon, let onAction {
                Button(action: onAction) {
                    Group {
                        if actionLabel == "微信登录" {
                            WeChatMark(size: 26)
                        } else {
                            Image(systemName: actionIcon)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.waterAccent)
                        }
                    }
                        .frame(width: 54, height: 54)
                        .background(
                            actionLabel == "微信登录" ? Color(hex: "E9F8F0") : Color.waterAccentPale,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white, lineWidth: 2))
                        .shadow(color: Color.platinum.opacity(0.7), radius: 0, x: 0, y: 5)
                }
                .accessibilityLabel(actionLabel ?? "打开")
            } else if showsMascot {
                Button(action: {}) {
                    KawaiiMascot(kind: mascot, size: 42)
                        .frame(width: 54, height: 54)
                        .background(Color.platinumLight)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white, lineWidth: 2))
                        .shadow(color: Color.platinum.opacity(0.7), radius: 0, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 18)
    }
}

/// A compact, platform-independent WeChat mark for the profile login action.
/// The real OAuth hand-off still belongs to the WeChat Open Platform integration.
private struct WeChatMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "message.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(Color(hex: "07C160"))
            Image(systemName: "message.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.58, height: size * 0.58)
                .foregroundStyle(.white)
                .offset(x: size * 0.16, y: size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String?
    var sticker: String? = nil
    var rule: Bool = false

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).roundedFont(20, weight: .heavy).foregroundStyle(Color.warmText)
                if let subtitle = subtitle { Text(subtitle).roundedFont(11).foregroundStyle(Color.mutedText) }
            }
            Spacer()
            if let sticker {
                Text(sticker).roundedFont(10, weight: .heavy).tracking(1).foregroundStyle(Color.inkSoft)
                    .padding(.horizontal, 11).frame(height: 29)
                    .background(Color.platinumLight, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .rotationEffect(.degrees(sticker == "NICE" ? -3 : 4))
            } else if rule {
                Rectangle().fill(Color.platinum).frame(width: 76, height: 4)
                    .mask(HStack(spacing: 7) { ForEach(0..<5, id: \.self) { _ in Capsule().frame(width: 12) } })
            }
        }
        .padding(.top, 37)
        .padding(.bottom, 16)
    }
}

private enum TrendSection: String, CaseIterable {
    case weight = "身体趋势"
    case measurements = "体围"
}

private struct TrendView: View {
    @ObservedObject var state: AppState
    @ObservedObject var health: HealthStore
    let onRecord: (RecordType) -> Void
    @State private var period: TrendPeriod = .month
    @State private var section: TrendSection = .weight
    @State private var bodyMetric: BodyMeasurementType = .waist
    @State private var isAddingMeasurement = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.platinumPale.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("身体趋势")
                            .roundedFont(28, weight: .heavy)
                            .foregroundStyle(Color.inkSoft)
                        Spacer()
                        Button { } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color.inkSoft)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 18)

                    HStack(spacing: 26) {
                        ForEach(TrendSection.allCases, id: \.self) { option in
                            Button { section = option } label: {
                                Text(option.rawValue)
                                    .roundedFont(17, weight: section == option ? .heavy : .medium)
                                    .foregroundStyle(section == option ? Color.inkSoft : Color.platinumDeep)
                                    .padding(.bottom, 11)
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill(Color.platinum)
                                            .frame(width: section == option ? 78 : 0, height: 7)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.top, 14)

                    if section == .weight {
                        weightTrendContent
                    } else {
                        BodyMeasurementSection(health: health, selectedType: $bodyMetric, onAdd: { isAddingMeasurement = true })
                            .padding(.top, 15)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 123)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isAddingMeasurement {
                CenteredModalOverlay(onDismiss: { isAddingMeasurement = false }) {
                    BodyMeasurementModal(
                        type: bodyMetric,
                        health: health,
                        onDismiss: { isAddingMeasurement = false }
                    )
                }
                .transition(.opacity)
                .zIndex(4)
            }
        }
    }

    private var weightTrendContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dateRange)
                    .roundedFont(18, weight: .bold)
                    .foregroundStyle(Color.inkSoft)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                Text("上午")
                    .roundedFont(16, weight: .bold)
                    .foregroundStyle(Color.inkSoft)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.inkSoft)
            }
            .padding(.top, 23)

            HStack(spacing: 6) {
                ForEach(TrendPeriod.allCases, id: \.self) { option in
                    Button { period = option } label: {
                        Text(option.rawValue)
                            .roundedFont(11, weight: period == option ? .bold : .medium)
                            .foregroundStyle(period == option ? Color.ink : Color.platinumDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 29)
                            .background(period == option ? Color.platinumLight : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.platinumPale, in: Capsule())
            .padding(.top, 12)

            HStack(spacing: 8) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("体重趋势")
                    .roundedFont(14, weight: .bold)
            }
            .foregroundStyle(Color.waterAccent)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Color.waterAccentPale, in: Capsule())
            .padding(.top, 21)

            VStack(alignment: .leading, spacing: 0) {
                WeightTrendChart(
                    records: filteredRecords,
                    goal: state.goalWeight,
                    maxPoints: filteredRecords.count
                )
                    .frame(height: 267)
                HStack {
                        ForEach(Array(chartLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .roundedFont(10, weight: .medium)
                            .foregroundStyle(Color.platinumDeep)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 7)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 1)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 10) {
                Text("阶段深度分析")
                    .roundedFont(19, weight: .heavy)
                    .foregroundStyle(Color.inkSoft)
                Text(analysisText)
                    .roundedFont(14, weight: .medium)
                    .foregroundStyle(Color.platinumDeep)
                    .lineSpacing(5)
                HStack {
                    Spacer()
                    Text("查看全部分析")
                        .roundedFont(14, weight: .bold)
                        .foregroundStyle(Color.inkSoft)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.inkSoft)
                }
                .padding(.top, 4)
            }
            .padding(18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .padding(.top, 4)

            HStack(alignment: .center) {
                Text("体重记录")
                    .roundedFont(19, weight: .heavy)
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                Button { onRecord(.weight) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.inkSoft)
                        .frame(width: 32, height: 32)
                    .background(Color.jellyMint.opacity(0.28), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 27)

            VStack(spacing: 0) {
                ForEach(Array(filteredRecords.prefix(5).enumerated()), id: \.element.id) { index, record in
                    HistoryRow(
                        record: record,
                        previous: previous(for: record),
                        unit: state.weightUnit
                    )
                        .padding(.horizontal, 12)
                    if index < min(4, filteredRecords.count - 1) {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.platinumLight, lineWidth: 1))
            .padding(.top, 10)
        }
    }

    private var filteredRecords: [WeightRecord] {
        let limit: Int
        switch period { case .week: limit = 7; case .month: limit = 30; case .quarter: limit = 90 }
        return Array(state.records.sorted { $0.date > $1.date }.prefix(limit))
    }

    private var dateRange: String {
        guard let latest = filteredRecords.first?.date, let earliest = filteredRecords.last?.date else { return "暂无记录" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: earliest)) - \(formatter.string(from: latest))"
    }

    private var chartLabels: [String] {
        guard !filteredRecords.isEmpty else { return ["暂无", "记录体重", "查看", "变化"] }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return [filteredRecords.last, filteredRecords.dropFirst(filteredRecords.count / 3).first, filteredRecords.dropFirst(filteredRecords.count * 2 / 3).first, filteredRecords.first].compactMap { $0 }.map { formatter.string(from: $0.date) }
    }

    private var analysisText: String {
        guard let latest = filteredRecords.first?.weight, let earliest = filteredRecords.last?.weight else { return "记录几次体重后，这里会生成你的阶段变化分析。" }
        let delta = latest - earliest
        let verb = delta <= 0 ? "下降" : "上升"
        return "这段时间共记录 \(filteredRecords.count) 次，体重\(verb) \(state.weightUnit.formatted(fromKilograms: abs(delta)))。目标体重为 \(state.weightUnit.formatted(fromKilograms: state.goalWeight))，继续保持稳定节奏。"
    }

    private func previous(for record: WeightRecord) -> WeightRecord? {
        let ordered = state.records.sorted { $0.date > $1.date }
        guard let index = ordered.firstIndex(where: { $0.id == record.id }), index + 1 < ordered.count else { return nil }
        return ordered[index + 1]
    }
}

private struct BodyMeasurementSection: View {
    @ObservedObject var health: HealthStore
    @Binding var selectedType: BodyMeasurementType
    let onAdd: () -> Void

    private var records: [BodyMeasurementRecord] { health.records(for: selectedType) }
    private var latest: BodyMeasurementRecord? { health.latestMeasurement(for: selectedType) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "体围数据", subtitle: "记录身体的温柔变化", sticker: "CM")

            Picker("体围指标", selection: $selectedType) {
                ForEach(BodyMeasurementType.allCases) { type in
                    Text(type.shortTitle).tag(type)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.inkSoft)
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(latest.map { String(format: "%.1f", $0.valueCm) } ?? "--")
                    .roundedFont(31, weight: .heavy)
                    .foregroundStyle(Color.warmText)
                Text("cm")
                    .roundedFont(11, weight: .bold)
                    .foregroundStyle(Color.mutedText)
                Spacer()
                Button(action: onAdd) {
                    Label("记录\(selectedType.title)", systemImage: "plus")
                        .roundedFont(11, weight: .bold)
                        .foregroundStyle(Color.inkSoft)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.platinumLight, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 15)
            .padding(.top, 13)

            MeasurementChart(records: records)
                .frame(height: 135)
                .padding(.horizontal, 15)
                .padding(.top, 15)
                .padding(.bottom, 15)
        }
        .padding(.bottom, 2)
        .kawaiiCard(radius: 23)
        .padding(.top, 18)
    }
}

private struct MeasurementChart: View {
    let records: [BodyMeasurementRecord]

    private var values: [Double] { Array(records.suffix(7).map(\.valueCm)) }

    var body: some View {
        GeometryReader { proxy in
            let minValue = (values.min() ?? 60) - 1
            let maxValue = (values.max() ?? 80) + 1
            let points = values.enumerated().map {
                point(index: $0.offset, value: $0.element, size: proxy.size, minValue: minValue, maxValue: maxValue)
            }

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(Color.platinumLight).frame(height: 1)
                        Spacer()
                    }
                }
                .padding(.vertical, 5)

                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(Color.waterAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.jellyPink)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(point)
                }

                if values.isEmpty {
                    Text("记录后，这里会出现体围趋势")
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(Color.mutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func point(index: Int, value: Double, size: CGSize, minValue: Double, maxValue: Double) -> CGPoint {
        let x = values.count == 1 ? size.width / 2 : CGFloat(index) / CGFloat(values.count - 1) * (size.width - 8) + 4
        let y = size.height - CGFloat((value - minValue) / max(0.1, maxValue - minValue)) * (size.height - 14) - 7
        return CGPoint(x: x, y: y)
    }
}

private struct BodyMeasurementModal: View {
    let type: BodyMeasurementType
    @ObservedObject var health: HealthStore
    let onDismiss: () -> Void
    @State private var whole: Int
    @State private var decimal: Int
    @State private var date: Date
    @State private var note = ""
    @State private var error = ""

    init(
        type: BodyMeasurementType,
        health: HealthStore,
        onDismiss: @escaping () -> Void
    ) {
        self.type = type
        self.health = health
        self.onDismiss = onDismiss
        let initialValue = health.latestMeasurement(for: type)?.valueCm ?? 70
        let parts = DecimalWeightValue.components(from: initialValue, wholeRange: 10...300)
        _whole = State(initialValue: parts.whole)
        _decimal = State(initialValue: parts.decimal)
        _date = State(initialValue: Calendar.current.startOfDay(for: .now))
    }

    var body: some View {
        InputModalSurface {
            VStack(alignment: .leading, spacing: 0) {
                InputModalHeader(
                    eyebrow: "身体记录",
                    title: "记录\(type.title)",
                    onDismiss: onDismiss
                )

                DecimalNumberPicker(
                    whole: $whole,
                    decimal: $decimal,
                    wholeRange: 10...300,
                    unit: "cm",
                    prompt: "滑动选择\(type.title)"
                )

                DateWheelSurface(date: $date)
                    .padding(.top, 8)

                ModalField(label: "备注", placeholder: "测量时间或状态（选填）", text: $note)
                    .padding(.top, 14)

                if !error.isEmpty {
                    Text(error)
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(Color(hex: "B64F5B"))
                        .padding(.top, 8)
                }

                InputModalSaveButton(title: "保存体围", action: save)
                    .padding(.top, 19)
            }
        }
    }

    private func save() {
        let parsed = DecimalWeightValue.value(whole: whole, decimal: decimal)
        guard health.addMeasurement(type: type, valueCm: parsed, date: recordDate, note: note) else {
            error = "请输入 10 至 300 cm 之间的数字"
            return
        }
        onDismiss()
    }

    private var recordDate: Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let now = calendar.dateComponents([.hour, .minute, .second], from: .now)
        return calendar.date(
            bySettingHour: now.hour ?? 9,
            minute: now.minute ?? 0,
            second: now.second ?? 0,
            of: day
        ) ?? day
    }
}

private struct HabitsView: View {
    @ObservedObject var health: HealthStore
    let onRecord: (RecordType) -> Void
    @State private var noteRecordingKind: HabitKind?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AppHeader(eyebrow: "TODAY'S HABITS", title: "把照顾自己变成习惯", mascot: .mintMochi)

                HabitProgressCard(completed: health.todayCompletedHabitCount)

                SectionHeader(title: "今日清单", subtitle: "完成一件，就给自己一个小小肯定", rule: true)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(HabitKind.allCases) { kind in
                        HabitTile(
                            kind: kind,
                            completed: health.isCompleted(kind, on: .now),
                            onToggle: { health.toggleHabit(kind) },
                            onDetail: {
                                if let type = kind.linkedRecordType {
                                    onRecord(type)
                                } else {
                                    noteRecordingKind = kind
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $noteRecordingKind) { kind in
            HabitRecordModal(kind: kind, health: health)
                .presentationDetents([.height(330)])
        }
    }
}

private struct HabitProgressCard: View {
    let completed: Int

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle().stroke(Color.platinumLight, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(completed) / 7)
                    .stroke(Color.jellyPink, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(completed)/7").roundedFont(15, weight: .heavy).foregroundStyle(Color.warmText)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(completed == 7 ? "今天全部完成啦" : "今天完成了 \(completed) 项")
                    .roundedFont(18, weight: .heavy)
                    .foregroundStyle(Color.warmText)
                Text(completed == 0 ? "从最容易的一项开始吧" : "慢慢来，每一步都算数")
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(Color.mutedText)
            }
            Spacer()
        }
        .padding(18)
        .kawaiiCard(radius: 23)
    }
}

private struct HabitTile: View {
    let kind: HabitKind
    let completed: Bool
    let onToggle: () -> Void
    let onDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: kind.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.waterAccent)
                    .frame(width: 38, height: 38)
                    .background(Color(hex: kind.tint), in: Circle())
                Spacer()
                Button(action: onToggle) {
                    ZStack {
                        Circle()
                            .fill(completed ? Color.jellyMint : Color.clear)
                        Circle()
                            .stroke(completed ? Color.clear : Color.platinum, lineWidth: 2)
                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 27, height: 27)
                }
                .buttonStyle(.plain)
            }
            Text(kind.title)
                .roundedFont(16, weight: .bold)
                .foregroundStyle(Color.warmText)
                .padding(.top, 13)
            Text(kind.subtitle)
                .roundedFont(10)
                .foregroundStyle(Color.mutedText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            Button("记录", action: onDetail)
                .roundedFont(10, weight: .bold)
                .foregroundStyle(Color.waterAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.waterAccentPale, in: Capsule())
                .buttonStyle(.plain)
                .padding(.top, 14)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 162, alignment: .topLeading)
        .background(completed ? Color.jellyMint.opacity(0.13) : Color.white, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(completed ? Color.jellyMint.opacity(0.45) : Color.platinumLight, lineWidth: 1)
        )
        .shadow(color: Color.platinum.opacity(0.17), radius: 8, y: 4)
        .opacity(completed ? 0.68 : 1)
    }
}

private struct HabitRecordModal: View {
    let kind: HabitKind
    @ObservedObject var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日记录")
                        .roundedFont(11, weight: .bold)
                        .foregroundStyle(Color.platinumDeep)
                    Text(kind.title)
                        .roundedFont(23, weight: .heavy)
                        .foregroundStyle(Color.warmText)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.inkSoft)
                        .frame(width: 34, height: 34)
                        .background(Color.platinumLight, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text(kind.subtitle)
                .roundedFont(12, weight: .medium)
                .foregroundStyle(Color.mutedText)
                .padding(.top, 17)

            ModalField(label: "备注", placeholder: notePlaceholder, text: $note)
                .padding(.top, 17)

            Button {
                health.recordHabit(kind, note: note)
                dismiss()
            } label: {
                Text("保存记录")
                    .roundedFont(15, weight: .heavy)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        LinearGradient(colors: [Color.jellyPink, Color.jellyBlue], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 19)
        }
        .padding(26)
        .background(Color.platinumPale)
    }

    private var notePlaceholder: String {
        switch kind {
        case .sleep: return "例如：23:30 入睡，睡眠 8 小时"
        case .bowelMovement: return "例如：早上一次，状态正常"
        case .medication: return "例如：早餐后按时服用"
        case .menstrualCycle: return "例如：今天是第 2 天"
        default: return "写下今天的状态（选填）"
        }
    }
}

private struct HistoryRow: View {
    let record: WeightRecord
    let previous: WeightRecord?
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 11) {
            VStack(spacing: 3) { Text(day).roundedFont(21, weight: .heavy).foregroundStyle(Color.inkSoft); Text(month).roundedFont(9).foregroundStyle(Color.mutedText) }.frame(width: 40)
            Circle().fill(Color.platinum).frame(width: 8, height: 8).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) { Text(unit.formatted(fromKilograms: record.weight)).roundedFont(14, weight: .heavy).foregroundStyle(Color.warmText); Text(record.note).roundedFont(10).foregroundStyle(Color.mutedText) }
            Spacer()
            Text(changeText).roundedFont(11, weight: .heavy).foregroundStyle(record.change < 0 ? Color(hex: "5EAA9E") : Color(hex: "D66B83"))
        }
        .frame(minHeight: 68)
    }

    private var day: String { String(Calendar.current.component(.day, from: record.date)) }
    private var month: String { "\(Calendar.current.component(.month, from: record.date))月" }
    private var changeText: String {
        guard abs(record.change) >= 0.05 else { return "—" }
        return "\(record.change > 0 ? "+" : "-")\(unit.formatted(fromKilograms: abs(record.change)))"
    }
}

private struct ProfileView: View {
    @ObservedObject var state: AppState
    @ObservedObject var health: HealthStore
    @ObservedObject var healthSync: HealthSyncCoordinator
    @ObservedObject var diet: DietStore
    let onShowAbout: () -> Void
    @State private var selectedAvatarItem: PhotosPickerItem?

    var body: some View {
        let currentAvatarData = state.avatarData
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        ProfileAvatar(data: currentAvatarData)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("更换头像")
                    Text("今天也很认真").roundedFont(20, weight: .heavy).foregroundStyle(Color.warmText).padding(.top, 18)
                    Text("已经坚持记录 \(state.records.count) 天").roundedFont(11).foregroundStyle(Color.mutedText).padding(.top, 5)
                    HStack(spacing: 0) {
                        ProfileStat(value: state.weightUnit.formattedValue(fromKilograms: max(0, state.startWeight - state.weight)), label: "已减 \(state.weightUnit.rawValue)")
                        Divider().frame(height: 40)
                        ProfileStat(value: "\(state.records.count)", label: "坚持天数")
                        Divider().frame(height: 40)
                        ProfileStat(value: state.weightUnit.formattedValue(fromKilograms: state.goalWeight), label: "目标 \(state.weightUnit.rawValue)")
                    }.padding(.top, 25).padding(.bottom, 4)
                }
                .padding(.top, 20).padding(.horizontal, 20).padding(.bottom, 20).kawaiiCard(radius: 24)
                VStack(spacing: 0) {
                    HealthKitConnectionCard(state: state, health: health, diet: diet, sync: healthSync)
                    Divider()
                    WeightUnitSettingsRow(state: state)
                    Divider()
                    SettingRow(
                        title: "关于这不得瘦死",
                        icon: "heart.fill",
                        action: onShowAbout
                    )
                }
                    .padding(.horizontal, 18).kawaiiCard(radius: 24).padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: selectedAvatarItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self) {
                    state.updateAvatar(data)
                }
                selectedAvatarItem = nil
            }
        }
    }
}

private struct ProfileAvatar: View {
    let data: Data?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
                .frame(width: 90, height: 90)
                .background(Color.panelPink, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white, lineWidth: 2))
                .shadow(color: Color.platinum.opacity(0.7), radius: 0, x: 0, y: 6)

            Image(systemName: "camera.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(Color.jellyPink, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .offset(x: 3, y: 3)
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        #if os(iOS)
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            KawaiiMascot(kind: .cloudKitty, size: 54)
        }
        #elseif os(macOS)
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            KawaiiMascot(kind: .cloudKitty, size: 54)
        }
        #endif
    }
}

private struct WeChatLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: WeChatAuthCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                WeChatMark(size: 30)
                    .frame(width: 42, height: 42)
                    .background(Color.mintPale, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("微信登录")
                        .roundedFont(22, weight: .heavy)
                        .foregroundStyle(Color.warmText)
                    Text("使用微信账号继续你的轻盈记录")
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(Color.mutedText)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.inkSoft)
                        .frame(width: 32, height: 32)
                        .background(Color.platinumLight, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text("登录后可在不同设备继续查看体重、趋势和习惯记录。")
                .roundedFont(13, weight: .medium)
                .foregroundStyle(Color.inkSoft)
                .lineSpacing(4)
                .padding(.top, 22)

            Button(action: openWeChat) {
                Label("使用微信登录", systemImage: auth.isConfigured ? "arrow.up.forward.app" : "gearshape")
                    .roundedFont(14, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        LinearGradient(colors: [Color.jellyMint, Color.waterAccent], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(auth.state == .opening)
            .padding(.top, 22)

            Text(auth.isConfigured
                 ? "将打开授权页面；完成微信授权后返回，登录状态会自动更新。"
                 : "微信登录暂不可用：需要配置开放平台 AppID、回调地址和服务端换 token。")
                .roundedFont(10, weight: .medium)
                .foregroundStyle(Color.mutedText)
                .lineSpacing(3)
                .padding(.top, 14)

            if !auth.statusMessage.isEmpty {
                Text(auth.statusMessage)
                    .roundedFont(10, weight: .bold)
                    .foregroundStyle(Color.waterAccent)
                    .padding(.top, 8)
            }
        }
        .padding(25)
        .background(Color.platinumPale)
        .onChange(of: auth.state) { _, state in
            if state == .authenticated { dismiss() }
        }
    }

    private func openWeChat() {
        auth.beginLogin()
    }
}

private struct HealthKitConnectionCard: View {
    @ObservedObject var state: AppState
    @ObservedObject var health: HealthStore
    @ObservedObject var diet: DietStore
    @ObservedObject var sync: HealthSyncCoordinator

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.inkSoft)
                .frame(width: 34, height: 34)
                .background(Color.platinumLight, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Apple 健康")
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(Color.warmText)
                Text(syncDetail)
                    .roundedFont(10)
                    .foregroundStyle(Color.mutedText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: startSync) {
                Group {
                    if sync.isSyncing {
                        ProgressView()
                            .tint(Color.inkSoft)
                    } else {
                        Text(sync.connectionState == .connected ? "再次同步" : "连接")
                            .roundedFont(11, weight: .bold)
                            .foregroundStyle(Color.inkSoft)
                    }
                }
                .frame(minWidth: 48, minHeight: 30)
                .background(Color.platinumLight, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sync.isSyncing || !sync.isAvailable)
        }
        .padding(.vertical, 14)
    }

    private func startSync() {
        Task {
            await sync.connectAndSync(appState: state, healthStore: health, dietStore: diet)
        }
    }

    private var syncDetail: String {
        guard sync.connectionState == .connected else { return sync.connectionState.detail }
        return "本次导入体重 \(sync.importedWeightCount) 条 · 饮食 \(sync.importedDietCount) 条 · 其他健康数据 \(sync.importedHabitCount) 项"
    }
}

private struct ProfileStat: View { let value: String; let label: String; var body: some View { VStack(spacing: 5) { Text(value).roundedFont(20, weight: .heavy).foregroundStyle(Color.strawberry).monospacedDigit().lineLimit(1).minimumScaleFactor(0.62); Text(label).roundedFont(10).foregroundStyle(Color.mutedText) }.frame(maxWidth: .infinity) } }

private struct WeightUnitSettingsRow: View {
    @ObservedObject var state: AppState

    private var selection: Binding<WeightUnit> {
        Binding(
            get: { state.weightUnit },
            set: { state.updateWeightUnit($0) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.waterAccent)
                .frame(width: 28, height: 28)
                .background(Color.waterAccentPale, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("体重单位")
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(Color.warmText)
                Text("首页、日历和趋势统一显示")
                    .roundedFont(10)
                    .foregroundStyle(Color.mutedText)
            }

            Spacer(minLength: 8)

            Picker("体重单位", selection: selection) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .tint(Color.waterAccent)
            .frame(width: 104)
            .accessibilityLabel("体重单位")
        }
        .frame(minHeight: 61)
    }
}

private struct SettingRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.strawberry)
                    .frame(width: 28, height: 28)
                    .background(Color.platinumLight, in: Circle())
                Text(title)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(Color.warmText)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.platinumDeep)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 61)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityHint("打开详情")
    }
}

private struct AboutQuoteModal: View {
    let onDismiss: () -> Void

    var body: some View {
        InputModalSurface {
            VStack(spacing: 0) {
                InputModalHeader(
                    eyebrow: "A LITTLE NOTE",
                    title: "关于这不得瘦死",
                    onDismiss: onDismiss
                )

                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.jellyPink)
                    .frame(width: 48, height: 48)
                    .background(Color.panelPink, in: Circle())
                    .padding(.top, 24)

                Text("人生でつまらない時っていうのは、神様からのバカンスなんです")
                    .roundedFont(18, weight: .bold)
                    .foregroundStyle(Color.warmText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .frame(maxWidth: 310)

                Button(action: onDismiss) {
                    Text("知道了")
                        .roundedFont(13, weight: .bold)
                        .foregroundStyle(Color.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.platinumLight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct BottomNav: View {
    @Binding var selected: AppTab

    var body: some View {
        HStack(spacing: 0) {
            navItem(.home)
            navItem(.diet)
            navItem(.trend)
            navItem(.mine)
        }
            .frame(maxWidth: 560)
            .padding(.horizontal, 26).padding(.top, 11).padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.98)).overlay(alignment: .top) { Rectangle().fill(Color.platinumLight).frame(height: 1) }.shadow(color: Color.platinum.opacity(0.22), radius: 18, y: -7)
    }

    private func navItem(_ tab: AppTab) -> some View {
        Button { selected = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: icon(for: tab)).font(.system(size: 18, weight: .bold))
                Text(tab.rawValue).roundedFont(10, weight: selected == tab ? .bold : .medium)
            }
            .foregroundStyle(selected == tab ? Color.waterAccent : Color.platinumDeep)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
    }

    private func icon(for tab: AppTab) -> String { switch tab { case .home: return "house.fill"; case .diet: return "fork.knife"; case .trend: return "chart.xyaxis.line"; case .mine: return "person.fill" } }
}

private struct KawaiiMascot: View {
    let kind: MascotKind
    let size: CGFloat

    var body: some View {
        let face = kind == .cloudKitty ? Color.white : Color.platinumLight
        ZStack {
            if kind == .berryBunny { ears(color: .white, bunny: true) }
            if kind == .puddingBear { ears(color: Color.platinum, bunny: false) }
            if kind == .cloudKitty { kittyEars() }
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(face).frame(width: size * 0.78, height: size * 0.62).offset(y: size * 0.10)
            HStack(spacing: size * 0.20) { Circle().fill(Color.inkSoft).frame(width: size * 0.07, height: size * 0.10); Circle().fill(Color.inkSoft).frame(width: size * 0.07, height: size * 0.10) }.offset(y: size * 0.08)
            Capsule().fill(Color.platinumDeep).frame(width: size * 0.14, height: size * 0.045).offset(y: size * 0.26)
        }.frame(width: size, height: size)
    }

    @ViewBuilder private func ears(color: Color, bunny: Bool) -> some View { HStack(spacing: size * 0.32) { RoundedRectangle(cornerRadius: size * 0.18).fill(color).frame(width: size * (bunny ? 0.22 : 0.24), height: size * (bunny ? 0.44 : 0.24)); RoundedRectangle(cornerRadius: size * 0.18).fill(color).frame(width: size * (bunny ? 0.22 : 0.24), height: size * (bunny ? 0.44 : 0.24)) }.offset(y: -size * 0.25) }
    @ViewBuilder private func kittyEars() -> some View { HStack(spacing: size * 0.28) { Triangle().fill(.white).frame(width: size * 0.28, height: size * 0.28); Triangle().fill(.white).frame(width: size * 0.28, height: size * 0.28) }.offset(y: -size * 0.22) }
}

private struct Triangle: Shape { func path(in rect: CGRect) -> Path { var path = Path(); path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.closeSubpath(); return path } }

private struct GoalWeightModal: View {
    @ObservedObject var state: AppState
    let onDismiss: () -> Void
    @State private var kilograms: Double
    @State private var unit: WeightUnit
    @State private var error = ""

    init(state: AppState, onDismiss: @escaping () -> Void) {
        self.state = state
        self.onDismiss = onDismiss
        _kilograms = State(initialValue: state.goalWeight)
        _unit = State(initialValue: state.weightUnit)
    }

    var body: some View {
        InputModalSurface {
            VStack(alignment: .leading, spacing: 0) {
                InputModalHeader(
                    eyebrow: "我的计划",
                    title: "设置目标体重",
                    onDismiss: onDismiss
                )

                WeightRulerPicker(
                    kilograms: $kilograms,
                    unit: $unit,
                    valueColor: { _ in Color.inkSoft }
                )

                if !error.isEmpty {
                    Text(error)
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(Color(hex: "B64F5B"))
                        .padding(.top, 8)
                }

                InputModalSaveButton(title: "保存目标", action: save)
                    .padding(.top, 20)
            }
        }
    }

    private func save() {
        guard state.updateGoalWeight(kilograms) else {
            error = "目标体重需在 \(unit.formatted(fromKilograms: WeightUnit.minimumKilograms)) 至 \(unit.formatted(fromKilograms: WeightUnit.maximumKilograms)) 之间"
            return
        }
        state.updateWeightUnit(unit)
        onDismiss()
    }
}

private struct RecordModal: View {
    let type: RecordType
    @ObservedObject var state: AppState
    let onDismiss: () -> Void
    @State private var kilograms: Double
    @State private var unit: WeightUnit
    @State private var date: Date
    @State private var name = ""
    @State private var amount = ""
    @State private var note = ""
    @State private var error = ""

    init(type: RecordType, state: AppState, onDismiss: @escaping () -> Void) {
        self.type = type; self.state = state; self.onDismiss = onDismiss
        _kilograms = State(initialValue: state.weight)
        _unit = State(initialValue: state.weightUnit)
        _date = State(initialValue: Calendar.current.startOfDay(for: .now))
    }

    var body: some View {
        InputModalSurface {
            VStack(alignment: .leading, spacing: 0) {
                InputModalHeader(
                    eyebrow: type == .weight ? "" : "添加记录",
                    title: type.title,
                    onDismiss: onDismiss,
                    centerTitle: type == .weight
                )

                if type == .weight {
                    WeightRulerPicker(
                        kilograms: $kilograms,
                        unit: $unit,
                        valueColor: { state.weightTone($0) }
                    )
                    DateWheelSurface(date: $date)
                        .padding(.top, 8)
                } else {
                    formFields
                }

                if !error.isEmpty {
                    Text(error)
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(Color(hex: "B64F5B"))
                        .padding(.top, 2)
                }

                InputModalSaveButton(title: type == .weight ? "保存" : "保存记录", action: save)
                    .padding(.top, 20)
            }
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModalField(label: type.nameLabel, placeholder: type.namePlaceholder, text: $name)
            HStack(alignment: .bottom, spacing: 9) { ModalField(label: type.amountLabel, placeholder: type.amountPlaceholder, text: $amount, keyboard: .decimalPad); Text(type.unit).roundedFont(12, weight: .bold).foregroundStyle(Color.mutedText).padding(.bottom, 15) }
            ModalField(label: "备注", placeholder: "写下今天的感受（选填）", text: $note)
        }.padding(.top, 24)
    }

    private func save() {
        if type == .weight {
            state.updateWeightUnit(unit)
            state.addWeight(
                kilograms,
                date: recordDate,
                note: note
            )
            onDismiss()
            return
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Double(amount) != nil else { error = "请把信息填写完整"; return }
        state.addActivity(type: type, name: name, amount: amount, note: note); onDismiss()
    }

    private var recordDate: Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let now = calendar.dateComponents([.hour, .minute, .second], from: .now)
        return calendar.date(
            bySettingHour: now.hour ?? 9,
            minute: now.minute ?? 0,
            second: now.second ?? 0,
            of: day
        ) ?? day
    }
}

private struct ModalField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: ModalKeyboard = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).roundedFont(11, weight: .bold).foregroundStyle(Color.inkSoft)
            inputField
                .roundedFont(13)
                .foregroundStyle(Color.warmText)
                .padding(.horizontal, 14)
                .frame(height: 45)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.platinum, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private var inputField: some View {
        #if os(iOS)
        TextField(placeholder, text: $text)
            .keyboardType(keyboard.uiType)
        #else
        TextField(placeholder, text: $text)
        #endif
    }
}

private enum ModalKeyboard {
    case `default`
    case decimalPad
}

#if os(iOS)
private extension ModalKeyboard {
    var uiType: UIKeyboardType {
        switch self {
        case .default: return .default
        case .decimalPad: return .decimalPad
        }
    }
}
#endif
