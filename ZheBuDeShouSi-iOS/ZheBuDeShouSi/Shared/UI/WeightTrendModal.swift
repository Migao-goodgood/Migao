import SwiftUI

/// Detail view presented from the home preview. The modal owns the period
/// control while the plot itself remains the only horizontally scrollable area.
struct WeightTrendModal: View {
    @ObservedObject var state: AppState
    let onDismiss: () -> Void
    @State private var period: TrendPeriod = .month

    var body: some View {
        InputModalSurface {
            VStack(alignment: .leading, spacing: 0) {
                InputModalHeader(
                    eyebrow: "体重变化",
                    title: "体重趋势",
                    onDismiss: onDismiss
                )

                Picker("趋势范围", selection: $period) {
                    ForEach(TrendPeriod.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color.waterAccent)
                .padding(.top, 18)
                .accessibilityLabel("选择趋势范围")

                WeightTrendPeriodPage(
                    records: records(for: period),
                    goal: state.chartGoalWeight,
                    showsGoal: state.hasConfiguredGoal,
                    period: period,
                    unit: state.weightUnit
                )
                .id(period)
                .padding(.top, 16)
            }
        }
    }

    private func records(for period: TrendPeriod) -> [WeightRecord] {
        let limit: Int
        switch period {
        case .week: limit = 7
        case .month: limit = 30
        case .quarter: limit = 90
        }
        return Array(state.records.sorted { $0.date > $1.date }.prefix(limit))
    }
}

private struct WeightTrendPeriodPage: View {
    let records: [WeightRecord]
    let goal: Double
    let showsGoal: Bool
    let period: TrendPeriod
    let unit: WeightUnit

    private var orderedRecords: [WeightRecord] {
        records.sorted { $0.date < $1.date }
    }

    private var chartWidth: CGFloat {
        let pointCount = max(1, orderedRecords.count)
        return max(340, CGFloat(max(1, pointCount - 1)) * 48 + 32)
    }

    private var summary: String {
        guard let first = orderedRecords.first?.weight,
              let latest = orderedRecords.last?.weight else {
            return "等待记录"
        }
        let delta = latest - first
        if abs(delta) < 0.05 { return "保持稳定" }
        return "\(delta < 0 ? "下降 " : "上升 ")\(unit.formatted(fromKilograms: abs(delta)))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(period.rawValue)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(Color.inkSoft)
                Spacer(minLength: 8)
                Text(summary)
                    .roundedFont(11, weight: .bold)
                    .foregroundStyle(summaryColor)
            }

            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    WeightTrendChart(
                        records: records,
                        goal: goal,
                        showsGoal: showsGoal,
                        maxPoints: recordLimit
                    )
                        .frame(width: chartWidth, height: 224)
                        .id("latest-trend-point")
                }
                .frame(height: 224)
                .onAppear {
                    DispatchQueue.main.async {
                        reader.scrollTo("latest-trend-point", anchor: .trailing)
                    }
                }
            }
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.platinumLight, lineWidth: 1)
            }

            if showsGoal {
                Text("目标 \(unit.formatted(fromKilograms: goal))")
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(Color.platinumDeep)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var recordLimit: Int {
        switch period {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }

    private var summaryColor: Color {
        guard let first = orderedRecords.first?.weight,
              let latest = orderedRecords.last?.weight else {
            return Color.platinumDeep
        }
        if abs(latest - first) < 0.05 {
            return Color.platinumDeep
        }
        return latest <= first ? Color.mintGreen : Color(hex: "D66B83")
    }
}

/// Shared line plot used by the home preview, the legacy trend workspace, and
/// the centered detail modal. A fixed width supplied by the caller makes it
/// safe to place inside a horizontal ScrollView.
struct WeightTrendChart: View {
    let records: [WeightRecord]
    let goal: Double
    var showsGoal = true
    var maxPoints: Int = 30

    private var plottedRecords: [WeightRecord] {
        Array(records.sorted { $0.date < $1.date }.suffix(max(1, maxPoints)))
    }

    private var values: [Double] {
        plottedRecords.map(\.weight)
    }

    var body: some View {
        GeometryReader { proxy in
            let fallback = values.first ?? goal
            let goalForScale = showsGoal ? goal : fallback
            let minValue = min((values.min() ?? fallback) - 0.5, goalForScale - 0.5)
            let maxValue = max((values.max() ?? fallback) + 0.5, goalForScale + 0.5)
            let points = values.enumerated().map { index, value in
                point(index: index, value: value, size: proxy.size, minValue: minValue, maxValue: maxValue)
            }

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.platinumLight)
                            .frame(height: 1)
                        Spacer()
                    }
                }
                .padding(.vertical, 5)

                if showsGoal {
                    let goalY = point(index: 0, value: goal, size: proxy.size, minValue: minValue, maxValue: maxValue).y
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: goalY))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: goalY))
                    }
                    .stroke(Color.platinum, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.platinum.opacity(0.58), Color.platinumPale.opacity(0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(Color.waterAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == points.count - 1 ? Color.jellyPink : Color.waterAccent)
                        .frame(
                            width: index == points.count - 1 ? 13 : 9,
                            height: index == points.count - 1 ? 13 : 9
                        )
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .position(point)
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

    private func point(
        index: Int,
        value: Double,
        size: CGSize,
        minValue: Double,
        maxValue: Double
    ) -> CGPoint {
        let horizontalInset: CGFloat = 8
        let x = values.count == 1
            ? size.width / 2
            : CGFloat(index) / CGFloat(values.count - 1)
                * max(0, size.width - horizontalInset * 2)
                + horizontalInset
        let y = size.height
            - CGFloat((value - minValue) / max(0.1, maxValue - minValue)) * (size.height - 12)
            - 6
        return CGPoint(x: x, y: y)
    }
}
