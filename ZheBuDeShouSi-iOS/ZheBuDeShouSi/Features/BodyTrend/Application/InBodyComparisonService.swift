import Foundation

/// Pure comparison use case shared by the dashboard, history detail, and
/// export surfaces. All arithmetic stays outside SwiftUI views.
struct InBodyComparisonService {
    private let metrics: [InBodyMetric]

    init(metrics: [InBodyMetric] = InBodyMetric.allCases) {
        self.metrics = metrics
    }

    func comparison(
        for current: InBodySnapshot,
        in snapshots: [InBodySnapshot],
        weightUnit: WeightUnit = .kilograms
    ) -> InBodyProgressComparison {
        let records = orderedUnique(snapshots + [current])
        guard let currentIndex = records.firstIndex(where: { $0.id == current.id }) else {
            return InBodyProgressComparison(
                currentSnapshotID: current.id,
                previous: nil,
                first: nil,
                analysis: insufficientAnalysis
            )
        }

        let previousSnapshot = currentIndex > 0 ? records[currentIndex - 1] : nil
        let firstSnapshot = currentIndex > 0 ? records[0] : nil
        let previousResult = previousSnapshot.map {
            compare(current: current, reference: $0, basis: .previous)
        }
        let firstResult = firstSnapshot.map {
            compare(current: current, reference: $0, basis: .first)
        }

        return InBodyProgressComparison(
            currentSnapshotID: current.id,
            previous: previousResult,
            first: firstResult,
            analysis: analyze(previous: previousResult, weightUnit: weightUnit)
        )
    }

    func compare(
        current: InBodySnapshot,
        reference: InBodySnapshot,
        basis: InBodyComparisonBaseline
    ) -> InBodyComparisonResult {
        let deltas = metrics.compactMap { metric -> InBodyMetricDelta? in
            guard let currentValue = metric.value(in: current), currentValue.isFinite,
                  let referenceValue = metric.value(in: reference), referenceValue.isFinite else {
                return nil
            }
            return InBodyMetricDelta(
                metric: metric,
                referenceValue: referenceValue,
                currentValue: currentValue,
                referenceDate: reference.date,
                currentDate: current.date
            )
        }

        return InBodyComparisonResult(
            basis: basis,
            currentSnapshotID: current.id,
            referenceSnapshotID: reference.id,
            currentDate: current.date,
            referenceDate: reference.date,
            deltas: deltas
        )
    }

    private func orderedUnique(_ snapshots: [InBodySnapshot]) -> [InBodySnapshot] {
        var byID: [UUID: InBodySnapshot] = [:]
        snapshots.forEach { byID[$0.id] = $0 }
        return byID.values.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.date < rhs.date
        }
    }

    private func analyze(
        previous: InBodyComparisonResult?,
        weightUnit: WeightUnit
    ) -> InBodyStageAnalysis {
        guard let previous else { return insufficientAnalysis }

        let weight = previous.delta(for: .weight)
        let bodyFatMass = previous.delta(for: .bodyFatMass)
        let bodyFatPercentage = previous.delta(for: .bodyFatPercentage)
        let muscle = previous.delta(for: .skeletalMuscle)
        let fatDeltas = [bodyFatMass, bodyFatPercentage].compactMap { $0 }
        let fatLoss = fatDeltas.contains { $0.direction == .decreased }
        let fatGain = fatDeltas.contains { $0.direction == .increased }
        let muscleLoss = muscle.map { $0.absoluteChange <= -0.3 } ?? false
        let muscleGain = muscle.map { $0.absoluteChange >= 0.2 } ?? false
        let core = InBodyMetric.coreTrendMetrics.compactMap { previous.delta(for: $0) }

        var highlights = core.compactMap { highlight(for: $0, weightUnit: weightUnit) }
        if highlights.isEmpty {
            highlights = ["两次报告缺少可共同对比的核心字段"]
        }

        if fatLoss, fatGain {
            return InBodyStageAnalysis(
                status: .mixed,
                headline: "体脂指标方向不一致",
                summary: "体脂肪量与体脂率出现不同方向的变化。请先核对报告数字，并结合下一次同条件测量再判断。",
                highlights: highlights
            )
        }

        if muscleLoss, (weight?.direction == .decreased || fatLoss) {
            return InBodyStageAnalysis(
                status: .attention,
                headline: "减重时留意肌肉变化",
                summary: "体重或体脂下降的同时，骨骼肌量也出现下降。建议先核对报告数字，并结合后续同条件测量观察。",
                highlights: highlights
            )
        }

        if fatLoss, muscleGain {
            return InBodyStageAnalysis(
                status: .improving,
                headline: "身体成分正在改善",
                summary: "体脂指标下降且骨骼肌量上升，这比只看体重更能反映本阶段的身体成分变化。",
                highlights: highlights
            )
        }

        if fatLoss, let muscle, muscle.direction != .decreased {
            return InBodyStageAnalysis(
                status: .improving,
                headline: "体脂下降，肌肉保持",
                summary: "体脂指标下降，骨骼肌量没有出现明显下降。请继续在相近条件下定期测量。",
                highlights: highlights
            )
        }

        if fatLoss, muscle == nil {
            return InBodyStageAnalysis(
                status: .insufficientData,
                headline: "体脂下降，待补充肌肉数据",
                summary: "本次体脂指标下降，但两份报告缺少可共同对比的骨骼肌量，暂不判断整体身体成分方向。",
                highlights: highlights
            )
        }

        if !core.isEmpty, core.allSatisfy({ $0.direction == .stable }) {
            return InBodyStageAnalysis(
                status: .stable,
                headline: "整体保持稳定",
                summary: "本次可对比的核心指标变化较小，继续积累同设备、相近条件下的记录更有参考价值。",
                highlights: highlights
            )
        }

        if core.count < 2 {
            return InBodyStageAnalysis(
                status: .insufficientData,
                headline: "还需要更多共同字段",
                summary: "两次报告可共同对比的核心指标较少，暂不做方向性判断。",
                highlights: highlights
            )
        }

        return InBodyStageAnalysis(
            status: .mixed,
            headline: "指标出现不同方向的变化",
            summary: "请同时观察体重、体脂和骨骼肌，不根据单个数字下结论。测量条件不同也可能造成短期波动。",
            highlights: highlights
        )
    }

    private var insufficientAnalysis: InBodyStageAnalysis {
        InBodyStageAnalysis(
            status: .insufficientData,
            headline: "完成下一次测量后开始对比",
            summary: "当前记录会作为阶段基线。建议使用同一台设备，并尽量保持测量时间、饮水和运动条件相近。"
        )
    }

    private func highlight(for delta: InBodyMetricDelta, weightUnit: WeightUnit) -> String? {
        switch delta.direction {
        case .stable:
            return "\(delta.metric.title)与上次基本持平"
        case .decreased, .increased:
            let direction = delta.direction == .decreased ? "下降" : "上升"
            let amount: String
            let unit: String
            if delta.metric == .weight {
                amount = weightUnit.formattedValue(fromKilograms: abs(delta.absoluteChange))
                unit = " \(weightUnit.rawValue)"
            } else {
                amount = format(abs(delta.absoluteChange), places: delta.metric.decimalPlaces)
                unit = delta.metric.changeUnit.isEmpty ? "" : " \(delta.metric.changeUnit)"
            }
            return "\(delta.metric.title)\(direction) \(amount)\(unit)"
        }
    }

    private func format(_ value: Double, places: Int) -> String {
        String(format: "%.*f", places, value)
    }
}
