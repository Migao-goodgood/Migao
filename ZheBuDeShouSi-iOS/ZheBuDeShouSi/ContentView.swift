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
            Color(hex: "F7F8FA")
                .ignoresSafeArea()

            Group {
                switch tab {
                case .home:
                    HomeView(state: state, health: health, onRecord: present, onEditGoal: presentGoalEditor)
                case .trend:
                    TrendView(state: state, health: health, onRecord: present)
                case .habits:
                    HabitsView(health: health, onRecord: present)
                case .mine:
                    ProfileView(state: state, health: health, healthSync: healthSync, onEditGoal: presentGoalEditor)
                }
            }
            .frame(maxWidth: usesWideLayout ? 720 : .infinity, maxHeight: .infinity, alignment: .top)

            BottomNav(selected: $tab, onWeigh: { present(.weight) })

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
}

private struct HomeView: View {
    @ObservedObject var state: AppState
    @ObservedObject var health: HealthStore
    let onRecord: (RecordType) -> Void
    let onEditGoal: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: "07A9E5"), Color(hex: "69C7EF"), Color(hex: "F7F8FA")], startPoint: .top, endPoint: .bottom)
                .frame(height: 470)
                .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HomeHeader(recordCount: state.records.count)
                    HomeWeightCard(state: state, onRecord: { onRecord(.weight) }, onEditGoal: onEditGoal)
                        .padding(.top, 9)

                    HomeTrendPreview(state: state)
                        .padding(.top, 18)

                    TodayRecordSection(state: state)
                        .padding(.top, 23)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 122)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct HomeHeader: View {
    let recordCount: Int

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Text("首页")
                    .roundedFont(28, weight: .heavy)
                Text("燃脂营")
                    .roundedFont(19, weight: .heavy)
                    .foregroundStyle(Color(hex: "FF8C38"))
                Text("饮食")
                    .roundedFont(18, weight: .bold)
                    .foregroundStyle(.white.opacity(0.72))
                Text("运动")
                    .roundedFont(18, weight: .bold)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
                ZStack(alignment: .bottomTrailing) {
                    Circle().fill(.white.opacity(0.9)).frame(width: 46, height: 46)
                    KawaiiMascot(kind: .berryBunny, size: 34)
                    Circle().fill(Color(hex: "FF8C38")).frame(width: 13, height: 13)
                        .overlay(Image(systemName: "ellipsis").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white))
                }
            }
            HStack(spacing: 6) {
                Circle().fill(.white.opacity(0.92)).frame(width: 5, height: 5)
                Text("已记录 \(recordCount) 天，今天也要轻盈一点")
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 15)
        .padding(.bottom, 4)
    }
}

private struct HomeWeightCard: View {
    @ObservedObject var state: AppState
    let onRecord: () -> Void
    let onEditGoal: () -> Void

    var body: some View {
        let gap = state.weightGap
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("21天前")
                    .roundedFont(13, weight: .medium)
                    .foregroundStyle(.white.opacity(0.76))
                Spacer()
                Text("今日体重")
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(.white.opacity(0.92))
            }

            HStack(alignment: .bottom, spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("距离目标")
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(gap >= 0 ? "+\(String(format: "%.1f", gap))" : "-\(String(format: "%.1f", abs(gap)))")
                        .roundedFont(26, weight: .heavy)
                        .foregroundStyle(gap > 0 ? Color(hex: "FFE2E8") : .white)
                    Text("kg")
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 8)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(String(format: "%.1f", state.weight))
                        .roundedFont(62, weight: .heavy)
                        .foregroundStyle(.white)
                    Text("kg")
                        .roundedFont(14, weight: .bold)
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("目标")
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(.white.opacity(0.72))
                    Button(action: onEditGoal) {
                        Text(String(format: "%.1f", state.goalWeight))
                            .roundedFont(24, weight: .heavy)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑目标体重")
                    Text("kg · 点击编辑")
                        .roundedFont(9, weight: .medium)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(.top, 17)

            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(height: 1)
                .padding(.top, 12)

            HStack(spacing: 5) {
                Image(systemName: gap > 0 ? "figure.walk" : "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Text(gap > 0 ? "慢慢来，距离目标还差一点点" : "太棒啦，已经达到目标体重")
                    .roundedFont(12, weight: .bold)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.top, 14)

            Button(action: onRecord) {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                    Text("记录今天的体重")
                        .roundedFont(13, weight: .heavy)
                }
                .foregroundStyle(Color(hex: "0B9DDD"))
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(hex: "16AEE8"), Color(hex: "52BFEF")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .shadow(color: Color(hex: "087EAE").opacity(0.22), radius: 18, y: 9)
    }
}

private struct HomeTrendPreview: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("查看趋势")
                        .roundedFont(17, weight: .heavy)
                        .foregroundStyle(Color(hex: "2D5268"))
                    Text("每一次记录，都会留下变化")
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(Color(hex: "8AA5B3"))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "65BCE4"))
            }
            TrendChart(records: state.records, goal: state.goalWeight)
                .frame(height: 94)
                .padding(.top, 9)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "93B8C9").opacity(0.14), radius: 14, y: 7)
    }
}

private struct TodayRecordSection: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .lastTextBaseline) {
                Text(todayTitle)
                    .roundedFont(18, weight: .heavy)
                    .foregroundStyle(Color(hex: "3D4D57"))
                Spacer()
                Text("最近记录 \(state.records.count) 条")
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(Color(hex: "9DA9B0"))
            }
            if let record = state.records.first {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color(hex: "DDF3FD"))
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(hex: "28AEE7"))
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("体重")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(Color(hex: "9AA6AD"))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", record.weight))
                                .roundedFont(28, weight: .heavy)
                                .foregroundStyle(state.weightTone(record.weight))
                            Text("kg")
                                .roundedFont(11, weight: .bold)
                                .foregroundStyle(Color(hex: "9AA6AD"))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(record.date, style: .time)
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(Color(hex: "8D9AA2"))
                        Text(record.change >= 0 ? "+\(String(format: "%.1f", record.change))" : String(format: "%.1f", record.change))
                            .roundedFont(12, weight: .heavy)
                            .foregroundStyle(record.change > 0 ? Color(hex: "E87582") : Color(hex: "42AA9B"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color(hex: "B2C1C9").opacity(0.15), radius: 12, y: 6)
            }
        }
    }

    private var todayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: .now)
    }
}

private struct AppHeader: View {
    let eyebrow: String
    let title: String
    let mascot: MascotKind

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow).roundedFont(11, weight: .bold).tracking(1.2).foregroundStyle(Color(hex: "ED84A9"))
                Text(title).roundedFont(27, weight: .heavy).foregroundStyle(Color.warmText).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(action: {}) {
                KawaiiMascot(kind: mascot, size: 42)
                    .frame(width: 54, height: 54)
                    .background(Color(hex: "FFD7E5"))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white, lineWidth: 2))
                    .shadow(color: Color(hex: "F6B9CE"), radius: 0, x: 0, y: 5)
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
                Text(sticker).roundedFont(10, weight: .heavy).tracking(1).foregroundStyle(sticker == "NICE" ? Color(hex: "8170C6") : Color(hex: "D85D8C"))
                    .padding(.horizontal, 11).frame(height: 29)
                    .background(sticker == "NICE" ? Color(hex: "E4DCFF") : Color(hex: "FFD9E6"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .rotationEffect(.degrees(sticker == "NICE" ? -3 : 4))
            } else if rule {
                Rectangle().fill(Color(hex: "FFB2CC")).frame(width: 76, height: 4)
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
            Color.white.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("身体趋势")
                            .roundedFont(28, weight: .heavy)
                            .foregroundStyle(Color(hex: "3F464D"))
                        Spacer()
                        Button { } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color(hex: "4F5961"))
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
                                    .foregroundStyle(section == option ? Color(hex: "3F464D") : Color(hex: "9DA5AB"))
                                    .padding(.bottom, 11)
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill(Color(hex: "BDE7FA"))
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
                    .foregroundStyle(Color(hex: "17A8E4"))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "17A8E4"))
                Spacer()
                Text("上午")
                    .roundedFont(16, weight: .bold)
                    .foregroundStyle(Color(hex: "17A8E4"))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "17A8E4"))
            }
            .padding(.top, 23)

            HStack(spacing: 6) {
                ForEach(TrendPeriod.allCases, id: \.self) { option in
                    Button { period = option } label: {
                        Text(option.rawValue)
                            .roundedFont(11, weight: period == option ? .bold : .medium)
                            .foregroundStyle(period == option ? Color(hex: "159FD7") : Color(hex: "9DA8AE"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 29)
                            .background(period == option ? Color(hex: "E2F6FD") : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color(hex: "F5F7F8"), in: Capsule())
            .padding(.top, 12)

            HStack(spacing: 12) {
                TrendMetricPill(title: "体重", icon: "scalemass.fill", selected: true)
                TrendMetricPill(title: "脂肪", icon: "drop.fill", selected: false)
                TrendMetricPill(title: "肌肉", icon: "figure.strengthtraining.traditional", selected: false)
            }
            .padding(.top, 21)

            VStack(alignment: .leading, spacing: 0) {
                TrendChart(records: filteredRecords, goal: state.goalWeight)
                    .frame(height: 267)
                HStack {
                    ForEach(chartLabels, id: \.self) { label in
                        Text(label)
                            .roundedFont(10, weight: .medium)
                            .foregroundStyle(Color(hex: "9FA8AE"))
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
                    .foregroundStyle(Color(hex: "3F464D"))
                Text(analysisText)
                    .roundedFont(14, weight: .medium)
                    .foregroundStyle(Color(hex: "626C73"))
                    .lineSpacing(5)
                HStack {
                    Spacer()
                    Text("查看全部分析")
                        .roundedFont(14, weight: .bold)
                        .foregroundStyle(Color(hex: "27AEE7"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "27AEE7"))
                }
                .padding(.top, 4)
            }
            .padding(18)
            .background(Color(hex: "F7F8F9"), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .padding(.top, 4)

            HStack(alignment: .center) {
                Text("体重记录")
                    .roundedFont(19, weight: .heavy)
                    .foregroundStyle(Color(hex: "3F464D"))
                Spacer()
                Button { onRecord(.weight) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "17A8E4"))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: "E4F6FD"), in: Circle())
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
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color(hex: "EDF0F2"), lineWidth: 1))
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

private struct TrendMetricPill: View {
    let title: String
    let icon: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
            Text(title).roundedFont(14, weight: selected ? .bold : .medium)
        }
        .foregroundStyle(selected ? .white : Color(hex: "A3A9AE"))
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(selected ? Color(hex: "20AFE9") : Color.clear, in: Capsule())
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
                VStack(spacing: 0) { ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color(hex: "EEF1F3")).frame(height: 1); Spacer() } }.padding(.vertical, 5)
                let goalY = point(index: 0, value: goal, size: proxy.size, minValue: minValue, maxValue: maxValue).y
                Path { path in
                    path.move(to: CGPoint(x: 0, y: goalY))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: goalY))
                }
                .stroke(Color(hex: "6AC5EC"), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Text("目标 \(String(format: "%.1f", goal))")
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(Color(hex: "65B8DC"))
                    .padding(.horizontal, 4)
                    .background(Color.white.opacity(0.86))
                    .position(x: proxy.size.width - 33, y: max(11, goalY - 12))
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                        path.closeSubpath()
                    }.fill(LinearGradient(colors: [Color(hex: "82D4F4").opacity(0.78), Color(hex: "DDF5FD").opacity(0.15)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }
                    }.stroke(Color(hex: "16A7E5"), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle().fill(index == points.count - 1 ? Color(hex: "0E9FDF") : Color(hex: "2AADE3")).frame(width: index == points.count - 1 ? 13 : 9, height: index == points.count - 1 ? 13 : 9).overlay(Circle().stroke(.white, lineWidth: 3)).position(point)
                }
                if points.isEmpty {
                    Text("记录体重后，这里会出现趋势")
                        .roundedFont(12, weight: .medium)
                        .foregroundStyle(Color(hex: "9AA6AD"))
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
            .tint(Color(hex: "D85687"))
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
                        .foregroundStyle(Color(hex: "D85687"))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color(hex: "FFE3EC"), in: Capsule())
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
                        Rectangle().fill(Color(hex: "F6E8EE")).frame(height: 1)
                        Spacer()
                    }
                }
                .padding(.vertical, 5)

                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(Color(hex: "EF7EA6"), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color(hex: "EF7EA6"))
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
                    Text("身体记录").roundedFont(11, weight: .bold).foregroundStyle(Color(hex: "E27CA2"))
                    Text("记录\(type.title)").roundedFont(23, weight: .heavy).foregroundStyle(Color.warmText)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "D27498"))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: "FFE0EB"), in: Circle())
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
                Text(error).roundedFont(11, weight: .medium).foregroundStyle(Color(hex: "D7587F")).padding(.top, 8)
            }

            Button(action: save) {
                Text("保存体围")
                    .roundedFont(15, weight: .heavy)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        LinearGradient(colors: [Color(hex: "F06F9E"), Color(hex: "F791B5")], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 19)
        }
        .padding(26)
        .background(Color(hex: "FFF8FB"))
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
                Circle().stroke(Color(hex: "F6DCE6"), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(completed) / 7)
                    .stroke(Color(hex: "EF7EA6"), style: StrokeStyle(lineWidth: 7, lineCap: .round))
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
                        .fill(completed ? Color(hex: "EF7EA6") : Color.clear)
                    Circle()
                        .stroke(completed ? Color.clear : Color(hex: "E9C7D5"), lineWidth: 2)
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
                .foregroundStyle(Color(hex: "D65F89"))
                .frame(width: 34, height: 34)
                .background(Color(hex: kind.tint), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).roundedFont(13, weight: .bold).foregroundStyle(Color.warmText)
                Text(kind.subtitle).roundedFont(10).foregroundStyle(Color.mutedText)
            }
            Spacer()

            Button("记录", action: onDetail)
                .roundedFont(10, weight: .bold)
                .foregroundStyle(Color(hex: "D65F89"))
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(Color(hex: "FFF0F5"), in: Capsule())
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
                        .foregroundStyle(Color(hex: "E27CA2"))
                    Text(kind.title)
                        .roundedFont(23, weight: .heavy)
                        .foregroundStyle(Color.warmText)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "D27498"))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: "FFE0EB"), in: Circle())
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
                        LinearGradient(colors: [Color(hex: "F06F9E"), Color(hex: "F791B5")], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 19)
        }
        .padding(26)
        .background(Color(hex: "FFF8FB"))
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
            VStack(spacing: 3) { Text(day).roundedFont(21, weight: .heavy).foregroundStyle(Color(hex: "E26491")); Text(month).roundedFont(9).foregroundStyle(Color.mutedText) }.frame(width: 40)
            Circle().fill(Color(hex: "F08BAD")).frame(width: 8, height: 8).frame(width: 22)
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
                    KawaiiMascot(kind: .cloudKitty, size: 54).frame(width: 90, height: 90).background(Color(hex: "FFD9E7"), in: RoundedRectangle(cornerRadius: 27, style: .continuous)).shadow(color: Color(hex: "EFBCCF"), radius: 0, x: 0, y: 6)
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
                .foregroundStyle(Color(hex: "D95D87"))
                .frame(width: 34, height: 34)
                .background(Color(hex: "FFE4ED"), in: Circle())

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
                            .tint(Color(hex: "D95D87"))
                    } else {
                        Text(sync.connectionState == .connected ? "再次同步" : "连接")
                            .roundedFont(11, weight: .bold)
                            .foregroundStyle(Color(hex: "D95D87"))
                    }
                }
                .frame(minWidth: 48, minHeight: 30)
                .background(Color(hex: "FFF0F5"), in: Capsule())
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
private struct SettingRow: View { let title: String; let icon: String; var body: some View { HStack { Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.strawberry).frame(width: 28, height: 28).background(Color(hex: "FFE3EC"), in: Circle()); Text(title).roundedFont(13, weight: .bold).foregroundStyle(Color.warmText); Spacer(); Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: "D9A5B9")) }.frame(height: 61) } }

private struct BottomNav: View {
    @Binding var selected: AppTab
    let onWeigh: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            navItem(.home)
            navItem(.trend)
            Button(action: onWeigh) {
                VStack(spacing: 3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Color(hex: "5ABCEC"))
                            .frame(width: 56, height: 56)
                            .shadow(color: Color(hex: "55A9D0").opacity(0.35), radius: 0, y: 5)
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("上秤")
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(Color(hex: "3F464D"))
                }
                .frame(maxWidth: .infinity)
                .offset(y: -17)
            }
            .buttonStyle(.plain)
            navItem(.habits)
            navItem(.mine)
        }
            .frame(maxWidth: 560)
            .padding(.horizontal, 26).padding(.top, 11).padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.98)).overlay(alignment: .top) { Rectangle().fill(Color(hex: "E8EEF1")).frame(height: 1) }.shadow(color: Color(hex: "7E9BAA").opacity(0.13), radius: 18, y: -7)
    }

    private func navItem(_ tab: AppTab) -> some View {
        Button { selected = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: icon(for: tab)).font(.system(size: 18, weight: .bold))
                Text(tab.rawValue).roundedFont(10, weight: selected == tab ? .bold : .medium)
            }
            .foregroundStyle(selected == tab ? Color(hex: "18A7E3") : Color(hex: "8B969E"))
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
        let face = kind == .puddingBear ? Color(hex: "FFE3A6") : kind == .mintMochi ? Color(hex: "D9EDC8") : .white
        ZStack {
            if kind == .berryBunny { ears(color: .white, bunny: true) }
            if kind == .puddingBear { ears(color: Color(hex: "E6BD79"), bunny: false) }
            if kind == .cloudKitty { kittyEars() }
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(face).frame(width: size * 0.78, height: size * 0.62).offset(y: size * 0.10)
            HStack(spacing: size * 0.20) { Circle().fill(Color(hex: "715563")).frame(width: size * 0.07, height: size * 0.10); Circle().fill(Color(hex: "715563")).frame(width: size * 0.07, height: size * 0.10) }.offset(y: size * 0.08)
            Capsule().fill(Color(hex: "F08BAC")).frame(width: size * 0.14, height: size * 0.045).offset(y: size * 0.26)
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
                        .foregroundStyle(Color(hex: "E27CA2"))
                    Text("设置目标体重")
                        .roundedFont(23, weight: .heavy)
                        .foregroundStyle(Color.warmText)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "D27498"))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: "FFE0EB"), in: Circle())
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
                    .foregroundStyle(Color(hex: "D7587F"))
                    .padding(.top, 8)
            }

            Button(action: save) {
                Text("保存目标")
                    .roundedFont(15, weight: .heavy)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(colors: [Color(hex: "F06F9E"), Color(hex: "F791B5")], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .shadow(color: Color(hex: "D95686"), radius: 0, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .padding(26)
        .frame(maxWidth: 350)
        .background(Color(hex: "FFF8FB"), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.95), lineWidth: 2))
        .shadow(color: Color(hex: "974569").opacity(0.22), radius: 28, y: 14)
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
                VStack(alignment: .leading, spacing: 5) { Text("添加记录").roundedFont(11, weight: .bold).foregroundStyle(Color(hex: "E27CA2")); Text(type.title).roundedFont(23, weight: .heavy).foregroundStyle(Color.warmText) }
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: "D27498")).frame(width: 34, height: 34).background(Color(hex: "FFE0EB"), in: Circle()) }.buttonStyle(.plain)
            }

            if type == .weight { WeightWheel(whole: $whole, decimal: $decimal) } else { formFields }
            if !error.isEmpty { Text(error).roundedFont(11, weight: .medium).foregroundStyle(Color(hex: "D7587F")).padding(.top, 2) }
            Button(action: save) { Text("保存记录").roundedFont(15, weight: .heavy).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52).background(LinearGradient(colors: [Color(hex: "F06F9E"), Color(hex: "F791B5")], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 17, style: .continuous)).shadow(color: Color(hex: "D95686"), radius: 0, x: 0, y: 6) }.buttonStyle(.plain).padding(.top, 20)
        }
        .padding(26)
        .frame(maxWidth: 350)
        .background(Color(hex: "FFF8FB"), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.95), lineWidth: 2))
        .shadow(color: Color(hex: "974569").opacity(0.22), radius: 28, y: 14)
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
                .foregroundStyle(Color(hex: "836777"))
                .frame(maxWidth: .infinity)
            pickerContainer
            .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color(hex: "F28AB0"), lineWidth: 1.5).frame(height: 55).allowsHitTesting(false) }
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
            .tint(Color(hex: "DF5F8D"))
            Picker("小数", selection: $decimal) {
                ForEach(0..<10, id: \.self) { Text(".\($0)").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 82, height: 170)
            .clipped()
            .tint(Color(hex: "DF5F8D"))
            Text("kg").roundedFont(13, weight: .heavy).foregroundStyle(Color(hex: "D76691")).padding(.leading, 4)
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
            Text("kg").roundedFont(13, weight: .heavy).foregroundStyle(Color(hex: "D76691"))
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
            Text(label).roundedFont(11, weight: .bold).foregroundStyle(Color(hex: "816877"))
            inputField
                .roundedFont(13)
                .foregroundStyle(Color.warmText)
                .padding(.horizontal, 14)
                .frame(height: 45)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: "F5DBE5"), lineWidth: 1.5))
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
