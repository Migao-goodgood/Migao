import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var healthSync: HealthSyncCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tab: AppTab = .home
    @State private var recordType: RecordType?
    @State private var isEditingGoal = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.platinumPale
                .ignoresSafeArea()

            Group {
                switch tab {
                case .home:
                    HomeView(state: state, onRecord: present, onEditGoal: presentGoalEditor, onShowTrend: showTrend)
                case .trend:
                    TrendView(state: state, health: health, onRecord: present)
                case .habits:
                    HabitsView(health: health, onRecord: present)
                case .mine:
                    ProfileView(state: state, health: health, healthSync: healthSync, onEditGoal: presentGoalEditor)
                }
            }
            .frame(maxWidth: usesWideLayout ? 720 : .infinity, maxHeight: .infinity, alignment: .top)

            BottomNav(selected: $tab)

            if let recordType {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { dismissRecord() }
                    .transition(.opacity)

                RecordModal(type: recordType, state: state, onDismiss: dismissRecord)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(2)
            }

            if isEditingGoal {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { dismissGoalEditor() }
                    .transition(.opacity)

                GoalWeightModal(state: state, onDismiss: dismissGoalEditor)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: recordType != nil)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isEditingGoal)
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

    private func showTrend() {
        withAnimation(.easeInOut(duration: 0.2)) { tab = .trend }
    }
}

private struct HomeView: View {
    @ObservedObject var state: AppState
    let onRecord: (RecordType) -> Void
    let onEditGoal: () -> Void
    let onShowTrend: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                HomePlanCard(state: state, onRecord: { onRecord(.weight) }, onEditGoal: onEditGoal)
                HomeTrendAndHistory(state: state, onShowTrend: onShowTrend)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 122)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.platinumPale.ignoresSafeArea())
    }
}

private struct HomePlanCard: View {
    @ObservedObject var state: AppState
    let onRecord: () -> Void
    let onEditGoal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("轻盈进度")
                        .roundedFont(26, weight: .heavy)
                        .foregroundStyle(Color.ink)
                    Text("把每天的记录，变成看得见的变化")
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(Color.platinumDeep)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("第 \(currentWeek) / 39 周")
                        .roundedFont(13, weight: .bold)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.waterAccentPale, in: Capsule())
                    Text("持续记录")
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(Color.platinumDeep)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(String(format: "%.1f", state.weight))
                    .roundedFont(43, weight: .heavy)
                    .foregroundStyle(state.weightTone(state.weight))
                Text("kg")
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(Color.waterAccent)
                Text("今日体重")
                    .roundedFont(12, weight: .medium)
                    .foregroundStyle(Color.platinumDeep)
                    .padding(.leading, 4)
                Spacer(minLength: 12)
                Button(action: onEditGoal) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("目标体重")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(Color.platinumDeep)
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(String(format: "%.1f", state.goalWeight))
                                .roundedFont(25, weight: .heavy)
                                .foregroundStyle(Color.ink)
                            Text("kg")
                                .roundedFont(11, weight: .bold)
                                .foregroundStyle(Color.platinumDeep)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑目标体重")
            }
            .padding(.top, 24)

            HomeProgressRail(progress: state.goalProgress)
                .frame(height: 16)
                .padding(.top, 22)

            HStack {
                Text(String(format: "起点 %.1f kg", state.startWeight))
                Spacer()
                Text(String(format: "已减 %.1f kg", max(0, state.startWeight - state.weight)))
                Spacer()
                Text(String(format: "终点 %.1f kg", state.goalWeight))
            }
            .roundedFont(10, weight: .medium)
            .foregroundStyle(Color.platinumDeep)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: state.weightGap > 0.05 ? "arrow.down.right" : "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 22, height: 22)
                    .background(Color.jellyMint.opacity(0.3), in: Circle())
                Text(progressSummary)
                    .roundedFont(11, weight: .bold)
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                Button(action: onRecord) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .heavy))
                        Text("记录体重")
                            .roundedFont(11, weight: .bold)
                    }
                    .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("记录今日体重")
            }
            .padding(.top, 17)
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

    private var currentWeek: Int {
        max(1, min(39, Int(ceil(Double(max(1, state.records.count)) / 7.0))))
    }

    private var progressSummary: String {
        if state.weightGap > 0.05 {
            return String(format: "距离目标还差 %.1f kg", state.weightGap)
        }
        if state.weightGap < -0.05 {
            return String(format: "已超过目标 %.1f kg", abs(state.weightGap))
        }
        return "已到达目标体重"
    }
}

private struct HomeProgressRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, progress))
            let width = max(0, proxy.size.width - 14)
            let markerOffset = width * clamped
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.platinumLight)
                Capsule()
                    .fill(LinearGradient(colors: [Color.jellyPink, Color.jellyBlue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(16, markerOffset + 14))
                Circle()
                    .fill(Color.ink)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: markerOffset)
            }
        }
        .frame(height: 14)
    }
}

private struct HomeTrendAndHistory: View {
    @ObservedObject var state: AppState
    let onShowTrend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onShowTrend) {
                HStack(alignment: .top, spacing: 12) {
                    Text("查看\n趋势")
                        .roundedFont(19, weight: .heavy)
                        .foregroundStyle(Color.waterAccent)
                        .lineSpacing(4)
                    Rectangle()
                        .fill(Color.platinum)
                        .frame(width: 2, height: 53)
                    TrendChart(records: state.records, goal: state.goalWeight)
                        .frame(height: 82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看趋势")
            .padding(.top, 17)
            .padding(.horizontal, 17)
            .padding(.bottom, 16)

            Rectangle()
                .fill(Color.platinumLight)
                .frame(height: 1)

            HomeWeightHistory(state: state)
                .padding(.horizontal, 17)
                .padding(.top, 16)
        }
        .padding(.bottom, 19)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .shadow(color: Color.platinum.opacity(0.23), radius: 17, y: 8)
    }
}

private struct HomeWeightHistory: View {
    @ObservedObject var state: AppState

    private var groups: [HomeDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: state.records) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { date in
            HomeDayGroup(date: date, records: (grouped[date] ?? []).sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("体重记录")
                    .roundedFont(18, weight: .heavy)
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                Text("共 \(state.records.count) 条")
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(Color.platinumDeep)
            }

            if groups.isEmpty {
                Text("记录体重后，这里会出现你的变化")
                    .roundedFont(13, weight: .medium)
                    .foregroundStyle(Color.platinumDeep)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 34)
            } else {
                ForEach(groups) { group in
                    Text(dayTitle(group.date))
                        .roundedFont(16, weight: .heavy)
                        .foregroundStyle(Color.inkSoft)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    ForEach(group.records) { record in
                        HomeWeightRow(record: record, state: state)
                        if record.id != group.records.last?.id {
                            Rectangle()
                                .fill(Color.platinumLight)
                                .frame(height: 1)
                                .padding(.leading, 53)
                        }
                    }
                }
            }
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

private struct HomeDayGroup: Identifiable {
    let date: Date
    let records: [WeightRecord]
    var id: Date { date }
}

private struct HomeWeightRow: View {
    let record: WeightRecord
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Circle()
                    .fill(Color.platinumPale)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.platinumDeep)
                    )
                Text(record.date, style: .time)
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(Color.platinumDeep)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("体重")
                        .roundedFont(12, weight: .medium)
                        .foregroundStyle(Color.platinumDeep)
                    Text(String(format: "%.1f", record.weight))
                        .roundedFont(29, weight: .heavy)
                        .foregroundStyle(state.weightTone(record.weight))
                    Text("kg")
                        .roundedFont(12, weight: .bold)
                        .foregroundStyle(Color.platinumDeep)
                }
                Text(record.note.isEmpty ? "记录体重" : record.note)
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(Color.platinumDeep)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(changeText)
                .roundedFont(12, weight: .heavy)
                .foregroundStyle(record.change > 0 ? Color(hex: "E47782") : Color(hex: "58A993"))
        }
        .padding(.vertical, 10)
    }

    private var changeText: String {
        guard abs(record.change) >= 0.05 else { return "—" }
        return String(format: "%+.1f", record.change)
    }
}

private struct AppHeader: View {
    let eyebrow: String
    let title: String
    let mascot: MascotKind

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow).roundedFont(11, weight: .bold).tracking(1.2).foregroundStyle(Color.waterAccent)
                Text(title).roundedFont(27, weight: .heavy).foregroundStyle(Color.warmText).lineLimit(2)
            }
            Spacer(minLength: 8)
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
        .padding(.vertical, 18)
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
        }
        .sheet(isPresented: $isAddingMeasurement) {
            BodyMeasurementModal(type: bodyMetric, health: health)
                .presentationDetents([.height(360)])
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
                TrendChart(records: filteredRecords, goal: state.goalWeight)
                    .frame(height: 267)
                HStack {
                    ForEach(chartLabels, id: \.self) { label in
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
                    HistoryRow(record: record, previous: previous(for: record))
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
        return Array(state.records.prefix(limit))
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
        return "这段时间共记录 \(filteredRecords.count) 次，体重\(verb) \(String(format: "%.1f", abs(delta))) kg。目标体重为 \(String(format: "%.1f", state.goalWeight)) kg，继续保持稳定节奏。"
    }

    private func previous(for record: WeightRecord) -> WeightRecord? {
        guard let index = state.records.firstIndex(where: { $0.id == record.id }), index + 1 < state.records.count else { return nil }
        return state.records[index + 1]
    }
}

private struct TrendChart: View {
    let records: [WeightRecord]
    let goal: Double
    private var values: [Double] { Array(records.prefix(30).reversed().map(\.weight)) }

    var body: some View {
        GeometryReader { proxy in
            let minValue = min((values.min() ?? goal) - 0.5, goal - 0.5)
            let maxValue = max((values.max() ?? goal) + 0.5, goal + 0.5)
            let points = values.enumerated().map { index, value in point(index: index, value: value, size: proxy.size, minValue: minValue, maxValue: maxValue) }
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) { ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color.platinumLight).frame(height: 1); Spacer() } }.padding(.vertical, 5)
                let goalY = point(index: 0, value: goal, size: proxy.size, minValue: minValue, maxValue: maxValue).y
                Path { path in
                    path.move(to: CGPoint(x: 0, y: goalY))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: goalY))
                }
                .stroke(Color.platinum, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Text("目标 \(String(format: "%.1f", goal))")
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(Color.platinumDeep)
                    .padding(.horizontal, 4)
                    .background(Color.white.opacity(0.86))
                    .position(x: proxy.size.width - 33, y: max(11, goalY - 12))
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                        path.closeSubpath()
                    }.fill(LinearGradient(colors: [Color.platinum.opacity(0.58), Color.platinumPale.opacity(0.18)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }
                    }.stroke(Color.waterAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle().fill(index == points.count - 1 ? Color.jellyPink : Color.waterAccent).frame(width: index == points.count - 1 ? 13 : 9, height: index == points.count - 1 ? 13 : 9).overlay(Circle().stroke(.white, lineWidth: 3)).position(point)
                }
                if points.isEmpty {
                    Text("记录体重后，这里会出现趋势")
                        .roundedFont(12, weight: .medium)
                        .foregroundStyle(Color.platinumDeep)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func point(index: Int, value: Double, size: CGSize, minValue: Double, maxValue: Double) -> CGPoint {
        let x = values.count == 1 ? size.width / 2 : CGFloat(index) / CGFloat(values.count - 1) * (size.width - 4) + 2
        let y = size.height - CGFloat((value - minValue) / max(0.1, maxValue - minValue)) * (size.height - 12) - 6
        return CGPoint(x: x, y: y)
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
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var note = ""
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("身体记录").roundedFont(11, weight: .bold).foregroundStyle(Color.platinumDeep)
                    Text("记录\(type.title)").roundedFont(23, weight: .heavy).foregroundStyle(Color.warmText)
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

            HStack(alignment: .bottom, spacing: 9) {
                ModalField(label: type.title, placeholder: "例如：72.5", text: $value, keyboard: .decimalPad)
                Text("cm").roundedFont(12, weight: .bold).foregroundStyle(Color.mutedText).padding(.bottom, 15)
            }
            .padding(.top, 24)

            ModalField(label: "备注", placeholder: "测量时间或状态（选填）", text: $note)
                .padding(.top, 14)

            if !error.isEmpty {
                Text(error).roundedFont(11, weight: .medium).foregroundStyle(Color(hex: "B64F5B")).padding(.top, 8)
            }

            Button(action: save) {
                Text("保存体围")
                    .roundedFont(15, weight: .heavy)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        LinearGradient(colors: [Color.inkSoft, Color.platinumDeep], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 19)
        }
        .padding(26)
        .background(Color.platinumPale)
    }

    private func save() {
        guard let parsed = Double(value.replacingOccurrences(of: ",", with: ".")), health.addMeasurement(type: type, valueCm: parsed, note: note) else {
            error = "请输入 10 至 300 cm 之间的数字"
            return
        }
        dismiss()
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
                VStack(spacing: 0) {
                    ForEach(HabitKind.allCases) { kind in
                        HabitRow(
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
                        if kind != HabitKind.allCases.last { Divider().padding(.leading, 59) }
                    }
                }
                .padding(.horizontal, 15)
                .kawaiiCard(radius: 23)
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

private struct HabitRow: View {
    let kind: HabitKind
    let completed: Bool
    let onToggle: () -> Void
    let onDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(completed ? Color.jellyMint : Color.clear)
                    Circle()
                        .stroke(completed ? Color.clear : Color.platinum, lineWidth: 2)
                    if completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 29, height: 29)
            }
            .buttonStyle(.plain)

            Image(systemName: kind.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.waterAccent)
                .frame(width: 34, height: 34)
                .background(Color.platinumLight, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).roundedFont(13, weight: .bold).foregroundStyle(Color.warmText)
                Text(kind.subtitle).roundedFont(10).foregroundStyle(Color.mutedText)
            }
            Spacer()

            Button("记录", action: onDetail)
                .roundedFont(10, weight: .bold)
                .foregroundStyle(Color.inkSoft)
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(Color.platinumLight, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.vertical, 13)
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

    var body: some View {
        HStack(spacing: 11) {
            VStack(spacing: 3) { Text(day).roundedFont(21, weight: .heavy).foregroundStyle(Color.inkSoft); Text(month).roundedFont(9).foregroundStyle(Color.mutedText) }.frame(width: 40)
            Circle().fill(Color.platinum).frame(width: 8, height: 8).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) { Text(String(format: "%.1f kg", record.weight)).roundedFont(14, weight: .heavy).foregroundStyle(Color.warmText); Text(record.note).roundedFont(10).foregroundStyle(Color.mutedText) }
            Spacer()
            Text(changeText).roundedFont(11, weight: .heavy).foregroundStyle(record.change < 0 ? Color(hex: "5EAA9E") : Color(hex: "D66B83"))
        }
        .frame(minHeight: 68)
    }

    private var day: String { String(Calendar.current.component(.day, from: record.date)) }
    private var month: String { "\(Calendar.current.component(.month, from: record.date))月" }
    private var changeText: String { abs(record.change) < 0.05 ? "—" : String(format: "%+.1f", record.change) }
}

private struct ProfileView: View {
    @ObservedObject var state: AppState
    @ObservedObject var health: HealthStore
    @ObservedObject var healthSync: HealthSyncCoordinator
    let onEditGoal: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                AppHeader(eyebrow: "MY KAWAII PLAN", title: "我的可爱变轻计划", mascot: .cloudKitty)
                VStack(spacing: 0) {
                    KawaiiMascot(kind: .cloudKitty, size: 54).frame(width: 90, height: 90).background(Color.platinumLight, in: RoundedRectangle(cornerRadius: 27, style: .continuous)).shadow(color: Color.platinum.opacity(0.7), radius: 0, x: 0, y: 6)
                    Text("今天也很认真").roundedFont(20, weight: .heavy).foregroundStyle(Color.warmText).padding(.top, 18)
                    Text("已经坚持记录 \(state.records.count) 天").roundedFont(11).foregroundStyle(Color.mutedText).padding(.top, 5)
                    HStack(spacing: 0) {
                        ProfileStat(value: String(format: "%.1f", max(0, state.startWeight - state.weight)), label: "已减 kg")
                        Divider().frame(height: 40)
                        ProfileStat(value: "\(state.records.count)", label: "坚持天数")
                        Divider().frame(height: 40)
                        ProfileStat(value: String(format: "%.1f", state.goalWeight), label: "目标 kg")
                    }.padding(.top, 25).padding(.bottom, 4)
                }
                .padding(.top, 35).padding(.horizontal, 20).padding(.bottom, 20).kawaiiCard(radius: 24)
                VStack(spacing: 0) {
                    Button(action: onEditGoal) { SettingRow(title: "目标设置", icon: "flag.fill") }.buttonStyle(.plain)
                    Divider()
                    HealthKitConnectionCard(state: state, health: health, sync: healthSync)
                    Divider()
                    SettingRow(title: "记录提醒", icon: "bell.fill")
                    Divider()
                    SettingRow(title: "关于这不得瘦死", icon: "heart.fill")
                }
                    .padding(.horizontal, 18).kawaiiCard(radius: 24).padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HealthKitConnectionCard: View {
    @ObservedObject var state: AppState
    @ObservedObject var health: HealthStore
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
            await sync.connectAndSync(appState: state, healthStore: health)
        }
    }

    private var syncDetail: String {
        guard sync.connectionState == .connected else { return sync.connectionState.detail }
        return "本次导入体重 \(sync.importedWeightCount) 条 · 习惯 \(sync.importedHabitCount) 项"
    }
}

private struct ProfileStat: View { let value: String; let label: String; var body: some View { VStack(spacing: 5) { Text(value).roundedFont(20, weight: .heavy).foregroundStyle(Color.strawberry); Text(label).roundedFont(10).foregroundStyle(Color.mutedText) }.frame(maxWidth: .infinity) } }
private struct SettingRow: View { let title: String; let icon: String; var body: some View { HStack { Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.strawberry).frame(width: 28, height: 28).background(Color.platinumLight, in: Circle()); Text(title).roundedFont(13, weight: .bold).foregroundStyle(Color.warmText); Spacer(); Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.platinumDeep) }.frame(height: 61) } }

private struct BottomNav: View {
    @Binding var selected: AppTab

    var body: some View {
        HStack(spacing: 0) {
            navItem(.home)
            navItem(.trend)
            navItem(.habits)
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

    private func icon(for tab: AppTab) -> String { switch tab { case .home: return "house.fill"; case .trend: return "chart.xyaxis.line"; case .habits: return "checkmark.circle.fill"; case .mine: return "person.fill" } }
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
    @State private var input: String
    @State private var error = ""

    init(state: AppState, onDismiss: @escaping () -> Void) {
        self.state = state
        self.onDismiss = onDismiss
        _input = State(initialValue: String(format: "%.1f", state.goalWeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("我的计划")
                        .roundedFont(11, weight: .bold)
                        .foregroundStyle(Color.platinumDeep)
                    Text("设置目标体重")
                        .roundedFont(23, weight: .heavy)
                        .foregroundStyle(Color.warmText)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.inkSoft)
                        .frame(width: 34, height: 34)
                        .background(Color.platinumLight, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: 9) {
                ModalField(label: "目标体重", placeholder: "例如：54.0", text: $input, keyboard: .decimalPad)
                Text("kg")
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(Color.mutedText)
                    .padding(.bottom, 15)
            }
            .padding(.top, 24)

            if !error.isEmpty {
                Text(error)
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(Color(hex: "B64F5B"))
                    .padding(.top, 8)
            }

            Button(action: save) {
                Text("保存目标")
                    .roundedFont(15, weight: .heavy)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(colors: [Color.jellyPink, Color.jellyBlue], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .shadow(color: Color.platinum.opacity(0.75), radius: 0, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .padding(26)
        .frame(maxWidth: 350)
        .background(Color.platinumPale, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.95), lineWidth: 2))
        .shadow(color: Color.platinum.opacity(0.32), radius: 28, y: 14)
    }

    private func save() {
        let normalized = input.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else {
            error = "请输入正确的体重数字"
            return
        }
        guard state.updateGoalWeight(value) else {
            error = "目标体重需在 20.0 至 300.0 kg 之间"
            return
        }
        onDismiss()
    }
}

private struct RecordModal: View {
    let type: RecordType
    @ObservedObject var state: AppState
    let onDismiss: () -> Void
    @State private var whole: Int
    @State private var decimal: Int
    @State private var name = ""
    @State private var amount = ""
    @State private var note = ""
    @State private var error = ""

    init(type: RecordType, state: AppState, onDismiss: @escaping () -> Void) {
        self.type = type; self.state = state; self.onDismiss = onDismiss
        let clamped = min(300, max(20, state.weight))
        _whole = State(initialValue: Int(clamped))
        _decimal = State(initialValue: min(9, max(0, Int((clamped * 10).rounded()) % 10)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) { Text("添加记录").roundedFont(11, weight: .bold).foregroundStyle(Color.platinumDeep); Text(type.title).roundedFont(23, weight: .heavy).foregroundStyle(Color.warmText) }
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.inkSoft).frame(width: 34, height: 34).background(Color.platinumLight, in: Circle()) }.buttonStyle(.plain)
            }

            if type == .weight { WeightWheel(whole: $whole, decimal: $decimal) } else { formFields }
            if !error.isEmpty { Text(error).roundedFont(11, weight: .medium).foregroundStyle(Color(hex: "B64F5B")).padding(.top, 2) }
            Button(action: save) { Text("保存记录").roundedFont(15, weight: .heavy).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52).background(LinearGradient(colors: [Color.inkSoft, Color.platinumDeep], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 17, style: .continuous)).shadow(color: Color.platinum.opacity(0.75), radius: 0, x: 0, y: 6) }.buttonStyle(.plain).padding(.top, 20)
        }
        .padding(26)
        .frame(maxWidth: 350)
        .background(Color.platinumPale, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.95), lineWidth: 2))
        .shadow(color: Color.platinum.opacity(0.32), radius: 28, y: 14)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModalField(label: type.nameLabel, placeholder: type.namePlaceholder, text: $name)
            HStack(alignment: .bottom, spacing: 9) { ModalField(label: type.amountLabel, placeholder: type.amountPlaceholder, text: $amount, keyboard: .decimalPad); Text(type.unit).roundedFont(12, weight: .bold).foregroundStyle(Color.mutedText).padding(.bottom, 15) }
            ModalField(label: "备注", placeholder: "写下今天的感受（选填）", text: $note)
        }.padding(.top, 24)
    }

    private func save() {
        if type == .weight { state.addWeight(Double("\(whole).\(decimal)") ?? state.weight, note: note); onDismiss(); return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Double(amount) != nil else { error = "请把信息填写完整"; return }
        state.addActivity(type: type, name: name, amount: amount, note: note); onDismiss()
    }
}

private struct WeightWheel: View {
    @Binding var whole: Int
    @Binding var decimal: Int
    var body: some View {
        VStack(spacing: 6) {
            Text(instructionText)
                .roundedFont(13, weight: .bold)
                .foregroundStyle(Color.inkSoft)
                .frame(maxWidth: .infinity)
            pickerContainer
            .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.platinum, lineWidth: 1.5).frame(height: 55).allowsHitTesting(false) }
            Text("精确到 0.1 kg").roundedFont(10).foregroundStyle(Color.mutedText)
        }
        .padding(.top, 22)
    }

    private var instructionText: String {
        #if os(iOS)
        return "滑动选择今天的体重"
        #else
        return "选择今天的体重"
        #endif
    }

    @ViewBuilder
    private var pickerContainer: some View {
        #if os(iOS)
        HStack(spacing: 0) {
            Picker("整数", selection: $whole) {
                ForEach(20...300, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 115, height: 170)
            .clipped()
            .tint(Color.inkSoft)
            Picker("小数", selection: $decimal) {
                ForEach(0..<10, id: \.self) { Text(".\($0)").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 82, height: 170)
            .clipped()
            .tint(Color.inkSoft)
            Text("kg").roundedFont(13, weight: .heavy).foregroundStyle(Color.inkSoft).padding(.leading, 4)
        }
        #else
        HStack(spacing: 8) {
            Picker("整数", selection: $whole) {
                ForEach(20...300, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            Picker("小数", selection: $decimal) {
                ForEach(0..<10, id: \.self) { Text(".\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            Text("kg").roundedFont(13, weight: .heavy).foregroundStyle(Color.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 55)
        #endif
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
