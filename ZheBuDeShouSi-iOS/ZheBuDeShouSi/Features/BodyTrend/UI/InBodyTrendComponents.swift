import SwiftUI

enum ComparisonSelection: String, CaseIterable, Identifiable {
    case previous
    case first

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previous: return "较上次"
        case .first: return "较首次"
        }
    }
}

struct InBodyLatestSummaryView: View {
    let latest: InBodySnapshot
    let recordCount: Int
    let progress: InBodyProgressComparison
    @Binding var selection: ComparisonSelection
    let weightUnit: WeightUnit

    private var comparison: InBodyComparisonResult? {
        selection == .previous ? progress.previous : progress.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最新测量")
                        .roundedFont(19, weight: .heavy)
                        .foregroundStyle(BodyEditorial.ink)
                    Text(InBodyFormatters.measurementDate.string(from: latest.date))
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(BodyEditorial.muted)
                }

                Spacer(minLength: 8)

                if recordCount > 1 {
                    Picker("对比基准", selection: $selection) {
                        ForEach(ComparisonSelection.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(BodyEditorial.blue)
                    .frame(width: 154)
                    .accessibilityLabel("选择身体数据对比基准")
                } else {
                    Text("第 1 次记录")
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(BodyEditorial.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(BodyEditorial.blueWash, in: Capsule())
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(InBodyMetric.coreTrendMetrics) { metric in
                    CoreMetricCard(
                        metric: metric,
                        currentValue: metric.value(in: latest),
                        delta: comparison?.delta(for: metric),
                        weightUnit: weightUnit
                    )
                }
            }

            if let comparison {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("对比 \(dateLabel(comparison.referenceDate)) 的已确认数据")
                        .roundedFont(10, weight: .medium)
                }
                .foregroundStyle(BodyEditorial.muted)
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

struct InBodyTrendSection: View {
    let snapshots: [InBodySnapshot]
    @Binding var selectedMetric: InBodyMetric
    let weightUnit: WeightUnit

    private var points: [InBodyTrendPoint] {
        snapshots.compactMap { snapshot in
            guard let value = selectedMetric.value(in: snapshot) else { return nil }
            return InBodyTrendPoint(id: snapshot.id, date: snapshot.date, value: value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Text("身体趋势")
                    .roundedFont(19, weight: .heavy)
                    .foregroundStyle(BodyEditorial.ink)
                Spacer()
                Text("共 \(snapshots.count) 次")
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(BodyEditorial.muted)
            }

            Picker("趋势指标", selection: $selectedMetric) {
                ForEach(InBodyMetric.coreTrendMetrics) { metric in
                    Text(shortMetricTitle(metric)).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .tint(BodyEditorial.blue)
            .accessibilityLabel("选择趋势指标")

            if points.count >= 2 {
                InBodyLineChart(points: points, metric: selectedMetric, weightUnit: weightUnit)
                    .frame(height: 205)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(BodyEditorial.blue)
                    Text(points.isEmpty ? "这一项还没有数据" : "再记录一次即可形成趋势")
                        .roundedFont(11, weight: .medium)
                        .foregroundStyle(BodyEditorial.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(BodyEditorial.blueWash.opacity(0.46), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func shortMetricTitle(_ metric: InBodyMetric) -> String {
        switch metric {
        case .weight: return "体重"
        case .bodyFatPercentage: return "体脂率"
        case .bodyFatMass: return "脂肪量"
        case .skeletalMuscle: return "骨骼肌"
        default: return metric.title
        }
    }
}

struct InBodyAssessmentView: View {
    let result: InBodyStageAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: result.status == .attention ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(result.status == .attention ? BodyEditorial.blush : BodyEditorial.sage)
                    .frame(width: 34, height: 34)
                    .background(BodyEditorial.blueWash, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("身体变化分析")
                        .roundedFont(11, weight: .bold)
                        .foregroundStyle(BodyEditorial.muted)
                    Text(result.headline)
                        .roundedFont(18, weight: .heavy)
                        .foregroundStyle(BodyEditorial.ink)
                }

                Spacer()

                Text(stageStatusTitle(result.status))
                    .roundedFont(9, weight: .bold)
                    .foregroundStyle(BodyEditorial.ink)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(BodyEditorial.sageWash, in: Capsule())
            }

            Text(result.summary)
                .roundedFont(12, weight: .medium)
                .foregroundStyle(BodyEditorial.ink)
                .lineSpacing(4)
                .padding(.top, 14)

            if !result.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.highlights, id: \.self) { item in
                        Label(item, systemImage: "checkmark")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(BodyEditorial.ink)
                    }
                }
                .padding(.top, 12)
            }

            Text(result.disclaimer)
                .roundedFont(9, weight: .medium)
                .foregroundStyle(BodyEditorial.muted)
                .padding(.top, 13)
        }
        .padding(16)
        .background(BodyEditorial.blushWash.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(BodyEditorial.blush).frame(width: 3)
        }
    }

    private func stageStatusTitle(_ status: InBodyStageStatus) -> String {
        switch status {
        case .insufficientData: return "继续记录"
        case .improving: return "趋势向好"
        case .stable: return "保持稳定"
        case .mixed: return "变化交错"
        case .attention: return "值得留意"
        }
    }
}

struct InBodyEmptyState: View {
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(BodyEditorial.blue)
                .frame(width: 76, height: 76)
                .background(BodyEditorial.blueWash, in: Circle())

            Text("还没有身体数据")
                .roundedFont(21, weight: .heavy)
                .foregroundStyle(BodyEditorial.ink)

            Text("第一份 InBody 报告等待收录")
                .roundedFont(12, weight: .medium)
                .foregroundStyle(BodyEditorial.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
        .background(BodyEditorial.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BodyEditorial.rule, lineWidth: 1)
        }
    }
}

private struct InBodyTrendPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

struct CoreMetricCard: View {
    let metric: InBodyMetric
    let currentValue: Double?
    let delta: InBodyMetricDelta?
    var weightUnit: WeightUnit = .kilograms

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle()
                    .fill(metricTint)
                    .frame(width: 6, height: 6)
                Text(metric.title)
                    .roundedFont(10, weight: .bold)
                    .foregroundStyle(BodyEditorial.muted)
            }

            Text(formatted(currentValue))
                .roundedFont(22, weight: .heavy)
                .foregroundStyle(BodyEditorial.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(deltaText)
                .roundedFont(10, weight: .bold)
                .foregroundStyle(deltaColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(13)
        .background(BodyEditorial.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle().fill(metricTint).frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var metricTint: Color {
        switch metric {
        case .weight: return BodyEditorial.blue
        case .bodyFatPercentage: return BodyEditorial.blush
        case .bodyFatMass: return BodyEditorial.gold
        case .skeletalMuscle: return BodyEditorial.sage
        default: return BodyEditorial.muted
        }
    }

    private var deltaText: String {
        guard let delta else { return "等待对比" }
        let change = delta.absoluteChange
        if abs(change) < 0.05 { return "与基准基本持平" }
        let arrow = change > 0 ? "↑" : "↓"
        let amount = metric == .weight
            ? weightUnit.formattedValue(fromKilograms: abs(change))
            : String(format: "%.*f", metric.decimalPlaces, abs(change))
        if metric == .bodyFatPercentage { return "\(arrow) \(amount) 个百分点" }
        let unit = metric == .weight ? weightUnit.rawValue : metric.unit
        return "\(arrow) \(amount) \(unit)"
    }

    private var deltaColor: Color {
        guard let change = delta?.absoluteChange, abs(change) >= 0.05 else { return BodyEditorial.muted }
        switch metric {
        case .bodyFatPercentage, .bodyFatMass:
            return change < 0 ? BodyEditorial.sage : BodyEditorial.blush
        case .skeletalMuscle:
            return change > 0 ? BodyEditorial.sage : BodyEditorial.blush
        default:
            return BodyEditorial.blue
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        let number = metric == .weight
            ? weightUnit.formattedValue(fromKilograms: value)
            : String(format: "%.*f", metric.decimalPlaces, value)
        let unit = metric == .weight ? weightUnit.rawValue : metric.unit
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

private struct InBodyLineChart: View {
    let points: [InBodyTrendPoint]
    let metric: InBodyMetric
    var weightUnit: WeightUnit = .kilograms

    private var tint: Color {
        switch metric {
        case .weight: return BodyEditorial.blue
        case .bodyFatPercentage: return BodyEditorial.blush
        case .bodyFatMass: return BodyEditorial.gold
        case .skeletalMuscle: return BodyEditorial.sage
        default: return BodyEditorial.blue
        }
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                if let latest = points.last {
                    Text(valueText(latest.value))
                        .roundedFont(21, weight: .heavy)
                        .foregroundStyle(BodyEditorial.ink)
                }
                Spacer()
                if let first = points.first, let latest = points.last {
                    Text(overallChange(from: first.value, to: latest.value))
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(BodyEditorial.muted)
                }
            }

            GeometryReader { proxy in
                let layout = chartLayout(in: proxy.size)
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        Path { path in
                            let y = layout.top + layout.plotHeight * CGFloat(index) / 3
                            path.move(to: CGPoint(x: layout.left, y: y))
                            path.addLine(to: CGPoint(x: layout.right, y: y))
                        }
                        .stroke(BodyEditorial.rule.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    }

                    Path { path in
                        for (index, point) in points.enumerated() {
                            let position = chartPoint(point, layout: layout)
                            if index == 0 { path.move(to: position) }
                            else { path.addLine(to: position) }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    ForEach(points) { point in
                        let position = chartPoint(point, layout: layout)
                        Circle()
                            .fill(BodyEditorial.paper)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(tint, lineWidth: 3))
                            .position(position)
                    }
                }
            }
            .frame(height: 125)

            HStack {
                if let first = points.first { Text(shortDate(first.date)) }
                Spacer()
                if let last = points.last { Text(shortDate(last.date)) }
            }
            .roundedFont(9, weight: .medium)
            .foregroundStyle(BodyEditorial.muted)
        }
        .padding(15)
        .background(BodyEditorial.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BodyEditorial.rule, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title)趋势，共 \(points.count) 次记录")
        .accessibilityValue(points.last.map { valueText($0.value) } ?? "暂无数据")
    }

    private struct Layout {
        let left: CGFloat
        let right: CGFloat
        let top: CGFloat
        let bottom: CGFloat
        let minValue: Double
        let maxValue: Double

        var plotWidth: CGFloat { right - left }
        var plotHeight: CGFloat { bottom - top }
    }

    private func chartLayout(in size: CGSize) -> Layout {
        let values = points.map(\.value)
        let rawMin = values.min() ?? 0
        let rawMax = values.max() ?? 1
        let rawRange = max(0.1, rawMax - rawMin)
        let padding = max(rawRange * 0.18, metric == .bodyFatPercentage ? 0.5 : 0.25)
        return Layout(
            left: 8,
            right: max(8, size.width - 8),
            top: 8,
            bottom: max(8, size.height - 8),
            minValue: rawMin - padding,
            maxValue: rawMax + padding
        )
    }

    private func chartPoint(_ point: InBodyTrendPoint, layout: Layout) -> CGPoint {
        let firstDate = points.first?.date.timeIntervalSinceReferenceDate ?? 0
        let lastDate = points.last?.date.timeIntervalSinceReferenceDate ?? firstDate
        let span = max(1, lastDate - firstDate)
        let xRatio = points.count == 1 ? 0.5 : (point.date.timeIntervalSinceReferenceDate - firstDate) / span
        let valueRange = max(0.1, layout.maxValue - layout.minValue)
        let yRatio = (point.value - layout.minValue) / valueRange
        return CGPoint(
            x: layout.left + layout.plotWidth * CGFloat(xRatio),
            y: layout.bottom - layout.plotHeight * CGFloat(yRatio)
        )
    }

    private func valueText(_ value: Double) -> String {
        let number = metric == .weight
            ? weightUnit.formattedValue(fromKilograms: value)
            : String(format: "%.*f", metric.decimalPlaces, value)
        let unit = metric == .weight ? weightUnit.rawValue : metric.unit
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private func overallChange(from first: Double, to latest: Double) -> String {
        let delta = latest - first
        if abs(delta) < 0.05 { return "阶段内基本持平" }
        let arrow = delta > 0 ? "↑" : "↓"
        let number = metric == .weight
            ? weightUnit.formattedValue(fromKilograms: abs(delta))
            : String(format: "%.*f", metric.decimalPlaces, abs(delta))
        let changeUnit = metric == .weight ? weightUnit.rawValue : metric.changeUnit
        let unit = changeUnit.isEmpty ? "" : " \(changeUnit)"
        return "较首次 \(arrow) \(number)\(unit)"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M.d"
        return formatter.string(from: date)
    }
}
