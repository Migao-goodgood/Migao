import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tab: AppTab = .home
    @State private var recordType: RecordType?
    @State private var isEditingGoal = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: "FFF5F8"), Color(hex: "FFFBFD")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            Group {
                switch tab {
                case .home:
                    HomeView(state: state, onRecord: present, onEditGoal: presentGoalEditor)
                case .trend:
                    TrendView(state: state, onRecord: present)
                case .mine:
                    ProfileView(state: state, onEditGoal: presentGoalEditor)
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
}

private struct HomeView: View {
    @ObservedObject var state: AppState
    let onRecord: (RecordType) -> Void
    let onEditGoal: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader(recordCount: state.records.count)
                WeightHero(state: state, onRecord: { onRecord(.weight) }, onEditGoal: onEditGoal)

                HomeSectionTitle(title: "今日状态", subtitle: "慢慢来，也是在向前")
                DailyPanel(water: state.water)

                HomeSectionTitle(title: "快捷记录", subtitle: "把今天的每一点努力收好")
                QuickRecordPanel(onRecord: onRecord)

                HomeSectionTitle(title: "最近记录", subtitle: "今天已留下 \(state.logs.count) 条记录")
                ActivityList(logs: state.logs)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HomeHeader: View {
    let recordCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("这不得瘦死")
                    .roundedFont(25, weight: .heavy)
                    .foregroundStyle(Color(hex: "4F3B46"))
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "F279A2"))
                        .frame(width: 5, height: 5)
                    Text("已认真记录 \(recordCount) 天")
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(Color(hex: "A48694"))
                }
            }
            Spacer(minLength: 8)
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(hex: "FFE2EC"))
                    .frame(width: 52, height: 52)
                KawaiiMascot(kind: .berryBunny, size: 38)
                    .offset(y: 1)
                Circle()
                    .fill(Color(hex: "72B7A8"))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72, alignment: .center)
    }
}

private struct WeightHero: View {
    @ObservedObject var state: AppState
    let onRecord: () -> Void
    let onEditGoal: () -> Void

    var body: some View {
        let remaining = max(0, state.weight - state.goalWeight)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    HStack(spacing: 7) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: "E2608E"))
                        Text("今日体重")
                            .roundedFont(13, weight: .bold)
                            .foregroundStyle(Color(hex: "765766"))
                    }
                    Spacer()
                    Button(action: onEditGoal) {
                        HStack(spacing: 5) {
                            Text("目标 \(String(format: "%.1f", state.goalWeight)) kg")
                            Image(systemName: "pencil")
                                .font(.system(size: 8, weight: .heavy))
                        }
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(Color(hex: "8D7180"))
                        .padding(.horizontal, 10)
                        .frame(height: 29)
                        .background(Color(hex: "FFF1F6"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑目标体重")
                }

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(String(format: "%.1f", state.weight))
                        .roundedFont(60, weight: .heavy)
                        .foregroundStyle(state.weightTone(state.weight))
                    Text("kg")
                        .roundedFont(14, weight: .bold)
                        .foregroundStyle(Color(hex: "9A7A89"))
                    Spacer(minLength: 6)
                    WeightChangeBadge(change: state.records.first?.change ?? 0)
                }
                .padding(.top, 13)

                HStack {
                    Text("距离目标还有 \(String(format: "%.1f", remaining)) kg")
                    Spacer()
                    Text("已完成 \(Int(state.goalProgress * 100))%")
                }
                .roundedFont(10, weight: .medium)
                .foregroundStyle(Color(hex: "9A7B89"))

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "F7E5EC"))
                        Capsule()
                            .fill(Color(hex: "ED7DA4"))
                            .frame(width: max(7, proxy.size.width * state.goalProgress))
                    }
                }
                .frame(height: 7)
                .padding(.top, 11)

                HStack {
                    Text("起点 \(String(format: "%.1f", state.startWeight))")
                    Spacer()
                    Text("终点 \(String(format: "%.1f", state.goalWeight))")
                }
                .roundedFont(9, weight: .medium)
                .foregroundStyle(Color(hex: "B094A1"))
                .padding(.top, 7)
            }
            .padding(20)

            Button(action: onRecord) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .heavy))
                    Text("记录今天的体重")
                        .roundedFont(13, weight: .bold)
                }
                .foregroundStyle(Color(hex: "D95080"))
                .frame(maxWidth: .infinity)
                .frame(height: 49)
                .background(Color(hex: "FFF0F5"))
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color(hex: "F4DCE6"), lineWidth: 1))
        .shadow(color: Color(hex: "B86C88").opacity(0.10), radius: 18, y: 8)
    }
}

private struct WeightChangeBadge: View {
    let change: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 9, weight: .heavy))
            Text(abs(change) < 0.05 ? "持平" : String(format: "%+.1f", change))
                .roundedFont(10, weight: .heavy)
        }
        .foregroundStyle(change <= 0 ? Color(hex: "4F9E8F") : Color(hex: "D45A73"))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(change <= 0 ? Color(hex: "E4F3EF") : Color(hex: "FCE8ED"), in: Capsule())
    }
}

private struct HomeSectionTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .roundedFont(17, weight: .heavy)
                .foregroundStyle(Color(hex: "55414B"))
            if let subtitle {
                Text(subtitle)
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(Color(hex: "A58B98"))
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 12)
    }
}

private struct DailyPanel: View {
    let water: Int

    var body: some View {
        HStack(spacing: 0) {
            MetricCell(icon: "flame.fill", color: Color(hex: "EA7A76"), tint: Color(hex: "FDEBE8"), value: "1280", unit: "kcal", label: "今日摄入")
            MetricDivider()
            MetricCell(icon: "drop.fill", color: Color(hex: "55A89C"), tint: Color(hex: "E2F3EF"), value: "\(water)", unit: "ml", label: "今日饮水")
            MetricDivider()
            MetricCell(icon: "figure.walk", color: Color(hex: "8D73C8"), tint: Color(hex: "EEE9F8"), value: "6842", unit: "步", label: "今日步数")
        }
        .padding(.vertical, 18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "F2E2E8"), lineWidth: 1))
    }
}

private struct MetricCell: View {
    let icon: String
    let color: Color
    let tint: Color
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(tint, in: Circle())
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).roundedFont(14, weight: .heavy).foregroundStyle(Color(hex: "5A444F"))
                Text(unit).roundedFont(8, weight: .medium).foregroundStyle(Color(hex: "A58B98"))
            }
            Text(label).roundedFont(9, weight: .medium).foregroundStyle(Color(hex: "9E8591"))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: "F0E3E8"))
            .frame(width: 1, height: 66)
    }
}

private struct QuickRecordPanel: View {
    let onRecord: (RecordType) -> Void

    var body: some View {
        HStack(spacing: 0) {
            QuickAction(type: .meal, label: "饮食", icon: "fork.knife", onTap: onRecord)
            QuickAction(type: .water, label: "喝水", icon: "drop.fill", onTap: onRecord)
            QuickAction(type: .sport, label: "运动", icon: "figure.walk", onTap: onRecord)
            QuickAction(type: .weight, label: "体重", icon: "scalemass.fill", onTap: onRecord)
        }
        .padding(.vertical, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "F2E2E8"), lineWidth: 1))
    }
}

private struct QuickAction: View {
    let type: RecordType
    let label: String
    let icon: String
    let onTap: (RecordType) -> Void

    var body: some View {
        Button { onTap(type) } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: 42, height: 42)
                    .background(tint, in: Circle())
                Text(label)
                    .roundedFont(10, weight: .bold)
                    .foregroundStyle(Color(hex: "755B68"))
            }
            .frame(maxWidth: .infinity, minHeight: 69)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tint: Color {
        switch type {
        case .meal: return Color(hex: "FDE7ED")
        case .water: return Color(hex: "E2F3EF")
        case .sport: return Color(hex: "FCEAE5")
        case .weight: return Color(hex: "EEE9F8")
        }
    }

    private var iconColor: Color {
        switch type {
        case .meal: return Color(hex: "DF668C")
        case .water: return Color(hex: "55A89C")
        case .sport: return Color(hex: "E27B6F")
        case .weight: return Color(hex: "8D73C8")
        }
    }
}

private struct ActivityList: View {
    let logs: [ActivityLog]

    var body: some View {
        let visibleLogs = Array(logs.prefix(5))
        VStack(spacing: 0) {
            ForEach(Array(visibleLogs.enumerated()), id: \.element.id) { index, log in
                HStack(spacing: 13) {
                    Image(systemName: icon(for: log.kind))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(iconColor(for: log.kind))
                        .frame(width: 38, height: 38)
                        .background(iconBackground(for: log.kind), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.title).roundedFont(12, weight: .bold).foregroundStyle(Color.warmText).lineLimit(1)
                        Text(log.note).roundedFont(10).foregroundStyle(Color.mutedText)
                    }
                    Spacer()
                    Text(log.amount).roundedFont(10, weight: .bold).foregroundStyle(Color(hex: "8D7280"))
                }
                .padding(.vertical, 13)
                if index < visibleLogs.count - 1 {
                    Rectangle().fill(Color(hex: "F2E5EA")).frame(height: 1).padding(.leading, 51)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "F2E2E8"), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for kind: RecordType) -> String { switch kind { case .meal: return "fork.knife"; case .water: return "drop.fill"; case .sport: return "figure.walk"; case .weight: return "scalemass.fill" } }
    private func iconColor(for kind: RecordType) -> Color { switch kind { case .meal: return .strawberry; case .water: return Color(hex: "66B7AE"); case .sport: return Color(hex: "8AB56B"); case .weight: return Color(hex: "9380CE") } }
    private func iconBackground(for kind: RecordType) -> Color { switch kind { case .meal: return .panelPink; case .water: return .mintPale; case .sport: return Color(hex: "E7F2D9"); case .weight: return .lavenderPale } }
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

private struct TrendView: View {
    @ObservedObject var state: AppState
    let onRecord: (RecordType) -> Void
    @State private var period: TrendPeriod = .week

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("WEIGHT TREND · DAY 18").roundedFont(11, weight: .bold).tracking(1.1).foregroundStyle(Color(hex: "ED84A9"))
                        Text("看见每一点小变化").roundedFont(27, weight: .heavy).foregroundStyle(Color.warmText).lineLimit(1).minimumScaleFactor(0.78)
                    }
                    Spacer()
                    Button { onRecord(.weight) } label: { Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: "D95888")).frame(width: 48, height: 48).background(Color(hex: "FFD9E7"), in: Circle()).shadow(color: Color(hex: "F0B8CD"), radius: 0, x: 0, y: 5) }
                    .buttonStyle(.plain)
                }
                .padding(.top, 22)
                Text("比起 7 天前，你已经轻了 \(String(format: "%.1f", period.loss)) kg").roundedFont(11).foregroundStyle(Color.mutedText).padding(.top, 8)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最新体重").roundedFont(10).foregroundStyle(Color.mutedText)
                            HStack(alignment: .lastTextBaseline, spacing: 4) { Text(String(format: "%.1f", state.weight)).roundedFont(32, weight: .heavy).foregroundStyle(state.weightTone(state.weight)); Text("kg").roundedFont(11).foregroundStyle(Color.mutedText) }
                        }
                        Spacer()
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: "55A99D")).frame(width: 30, height: 30).background(Color.mintPale, in: Circle())
                            VStack(alignment: .leading, spacing: 2) { Text(String(format: "%.1f kg", period.loss)).roundedFont(12, weight: .heavy).foregroundStyle(Color(hex: "55A99D")); Text("本周期").roundedFont(9).foregroundStyle(Color.mutedText) }
                        }
                    }

                    PickerBar(period: $period)
                    TrendChart(records: state.records)
                        .frame(height: 186)
                        .padding(.top, 18)
                    HStack { ForEach(chartLabels, id: \.self) { Text($0).roundedFont(9).foregroundStyle(Color.mutedText).frame(maxWidth: .infinity) } }
                        .padding(.top, 1)
                        .padding(.bottom, 17)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .kawaiiCard(radius: 24)
                .padding(.top, 16)

                HStack(spacing: 0) {
                    TrendStat(label: "平均体重", value: averageWeight)
                    Divider().frame(height: 40)
                    TrendStat(label: "最低体重", value: state.records.map(\.weight).min() ?? state.weight)
                    Divider().frame(height: 40)
                    TrendStat(label: "连续记录", value: Double(state.records.count), unit: "天")
                }
                .padding(.vertical, 17)
                .kawaiiCard(radius: 22)
                .padding(.top, 14)

                SectionHeader(title: "体重记录", subtitle: "规律记录，更容易看见变化")
                VStack(spacing: 0) {
                    ForEach(Array(state.records.enumerated()), id: \.element.id) { index, record in
                        HistoryRow(record: record, previous: previous(for: record))
                        if index < state.records.count - 1 { Rectangle().fill(Color(hex: "F3E2E9")).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 17)
                .kawaiiCard(radius: 23)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var averageWeight: Double { state.records.map(\.weight).reduce(0, +) / Double(max(1, state.records.count)) }
    private var chartLabels: [String] { ["8/06", "8/08", "8/10", "今天"] }
    private func previous(for record: WeightRecord) -> WeightRecord? { guard let index = state.records.firstIndex(where: { $0.id == record.id }), index + 1 < state.records.count else { return nil }; return state.records[index + 1] }
}

private struct TrendStat: View {
    let label: String
    let value: Double
    var unit: String = "kg"

    var body: some View {
        VStack(spacing: 5) {
            Text(label).roundedFont(10).foregroundStyle(Color.mutedText)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(unit == "kg" ? String(format: "%.1f", value) : String(format: "%.0f", value)).roundedFont(17, weight: .heavy).foregroundStyle(Color.warmText)
                Text(unit).roundedFont(9).foregroundStyle(Color.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PickerBar: View {
    @Binding var period: TrendPeriod

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TrendPeriod.allCases, id: \.self) { option in
                Button { period = option } label: {
                    Text(option.rawValue).roundedFont(11, weight: period == option ? .bold : .medium).foregroundStyle(period == option ? Color(hex: "D85687") : .mutedText).frame(maxWidth: .infinity, minHeight: 31).background(period == option ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(hex: "F2E4EC"), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(.top, 16)
    }
}

private struct TrendChart: View {
    let records: [WeightRecord]
    private var values: [Double] { Array(records.prefix(7).reversed().map(\.weight)) }

    var body: some View {
        GeometryReader { proxy in
            let minValue = (values.min() ?? 54) - 0.5
            let maxValue = (values.max() ?? 60) + 0.5
            let points = values.enumerated().map { index, value in point(index: index, value: value, size: proxy.size, minValue: minValue, maxValue: maxValue) }
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in Rectangle().fill(Color(hex: "F6E8EE")).frame(height: 1); Spacer() } }.padding(.vertical, 5)
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                        path.closeSubpath()
                    }.fill(LinearGradient(colors: [Color(hex: "FFD7E5").opacity(0.72), .clear], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }
                    }.stroke(Color(hex: "EF7EA6"), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle().fill(index == points.count - 1 ? Color(hex: "806FC4") : Color(hex: "EF7EA6")).frame(width: index == points.count - 1 ? 13 : 10, height: index == points.count - 1 ? 13 : 10).overlay(Circle().stroke(.white, lineWidth: 3)).position(point)
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

private struct ProfileStat: View { let value: String; let label: String; var body: some View { VStack(spacing: 5) { Text(value).roundedFont(20, weight: .heavy).foregroundStyle(Color.strawberry); Text(label).roundedFont(10).foregroundStyle(Color.mutedText) }.frame(maxWidth: .infinity) } }
private struct SettingRow: View { let title: String; let icon: String; var body: some View { HStack { Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.strawberry).frame(width: 28, height: 28).background(Color(hex: "FFE3EC"), in: Circle()); Text(title).roundedFont(13, weight: .bold).foregroundStyle(Color.warmText); Spacer(); Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: "D9A5B9")) }.frame(height: 61) } }

private struct BottomNav: View {
    @Binding var selected: AppTab
    var body: some View {
        HStack(spacing: 0) { ForEach(AppTab.allCases, id: \.self) { tab in Button { selected = tab } label: { VStack(spacing: 5) { Image(systemName: icon(for: tab)).font(.system(size: 17, weight: .bold)); Text(tab.rawValue).roundedFont(10, weight: selected == tab ? .bold : .medium) }.foregroundStyle(selected == tab ? Color(hex: "E45F8E") : Color(hex: "B49CA8")).frame(maxWidth: .infinity).frame(height: 57) }.buttonStyle(.plain) } }
            .frame(maxWidth: 560)
            .padding(.horizontal, 44).padding(.top, 9).padding(.bottom, 3)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.96)).overlay(alignment: .top) { Rectangle().fill(Color(hex: "F4D7E3")).frame(height: 1) }.shadow(color: Color(hex: "DA8BA9").opacity(0.11), radius: 18, y: -7)
    }
    private func icon(for tab: AppTab) -> String { switch tab { case .home: return "house.fill"; case .trend: return "chart.xyaxis.line"; case .mine: return "person.fill" } }
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
