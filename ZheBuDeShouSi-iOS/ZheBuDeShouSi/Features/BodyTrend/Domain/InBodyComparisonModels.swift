import Foundation

/// Stable metric identifiers used by charts, report details, and comparisons.
/// Report recommendations such as target weight are deliberately excluded:
/// they are machine suggestions, not observed body-composition measurements.
enum InBodyMetric: String, Codable, CaseIterable, Identifiable, Hashable {
    case weight
    case bodyFatMass
    case bodyFatPercentage
    case skeletalMuscle
    case bmi
    case waistHipRatio
    case visceralFatLevel
    case score
    case totalBodyWater
    case protein
    case mineral
    case fatFreeMass
    case bodyCellMass
    case basalMetabolicRate
    case smi

    var id: String { rawValue }

    static let coreTrendMetrics: [InBodyMetric] = [
        .weight,
        .bodyFatPercentage,
        .bodyFatMass,
        .skeletalMuscle
    ]

    static let overviewMetrics: [InBodyMetric] = coreTrendMetrics + [
        .bmi,
        .waistHipRatio,
        .visceralFatLevel,
        .score
    ]

    var title: String {
        switch self {
        case .weight: return "体重"
        case .bodyFatMass: return "体脂肪量"
        case .bodyFatPercentage: return "体脂率"
        case .skeletalMuscle: return "骨骼肌量"
        case .bmi: return "BMI"
        case .waistHipRatio: return "腰臀比"
        case .visceralFatLevel: return "内脏脂肪等级"
        case .score: return "InBody 评分"
        case .totalBodyWater: return "总体水分"
        case .protein: return "蛋白质"
        case .mineral: return "矿物质"
        case .fatFreeMass: return "去脂体重"
        case .bodyCellMass: return "身体细胞量"
        case .basalMetabolicRate: return "基础代谢率"
        case .smi: return "SMI"
        }
    }

    var unit: String {
        switch self {
        case .weight, .bodyFatMass, .skeletalMuscle, .protein, .mineral,
             .fatFreeMass, .bodyCellMass:
            return "kg"
        case .bodyFatPercentage:
            return "%"
        case .totalBodyWater:
            return "L"
        case .basalMetabolicRate:
            return "kcal"
        case .bmi, .smi:
            return "kg/m²"
        case .visceralFatLevel:
            return "级"
        case .score:
            return "分"
        case .waistHipRatio:
            return ""
        }
    }

    /// Body-fat percentage values use `%`, while their difference is measured
    /// in percentage points. Other metrics keep the same value/change unit.
    var changeUnit: String {
        self == .bodyFatPercentage ? "个百分点" : unit
    }

    var decimalPlaces: Int {
        switch self {
        case .waistHipRatio, .mineral:
            return 2
        case .visceralFatLevel, .score, .basalMetabolicRate:
            return 0
        default:
            return 1
        }
    }

    /// Changes smaller than this are shown as stable to avoid turning normal
    /// rounding noise into a meaningful trend.
    var comparisonTolerance: Double {
        switch self {
        case .waistHipRatio, .mineral:
            return 0.01
        case .visceralFatLevel, .score:
            return 0.5
        case .basalMetabolicRate:
            return 5
        default:
            return 0.1
        }
    }

    func value(in snapshot: InBodySnapshot) -> Double? {
        switch self {
        case .weight: return snapshot.weightKg
        case .bodyFatMass: return snapshot.bodyFatKg
        case .bodyFatPercentage: return snapshot.bodyFatPercentage
        case .skeletalMuscle: return snapshot.skeletalMuscleKg
        case .bmi: return snapshot.bmi
        case .waistHipRatio: return snapshot.waistHipRatio
        case .visceralFatLevel: return snapshot.visceralFatLevel
        case .score: return snapshot.score
        case .totalBodyWater: return snapshot.totalBodyWaterL
        case .protein: return snapshot.proteinKg
        case .mineral: return snapshot.mineralKg
        case .fatFreeMass: return snapshot.fatFreeMassKg
        case .bodyCellMass: return snapshot.bodyCellMassKg
        case .basalMetabolicRate: return snapshot.basalMetabolicRate
        case .smi: return snapshot.smiKgPerM2
        }
    }
}

enum InBodyChangeDirection: String, Codable, Equatable {
    case decreased
    case stable
    case increased
}

struct InBodyMetricDelta: Identifiable, Codable, Equatable {
    var id: InBodyMetric { metric }
    let metric: InBodyMetric
    let referenceValue: Double
    let currentValue: Double
    let absoluteChange: Double
    let relativeChangePercent: Double?
    let direction: InBodyChangeDirection
    let referenceDate: Date
    let currentDate: Date

    init(
        metric: InBodyMetric,
        referenceValue: Double,
        currentValue: Double,
        referenceDate: Date,
        currentDate: Date
    ) {
        let change = currentValue - referenceValue
        self.metric = metric
        self.referenceValue = referenceValue
        self.currentValue = currentValue
        self.absoluteChange = change
        self.relativeChangePercent = referenceValue == 0 ? nil : change / referenceValue * 100
        self.direction = abs(change) < metric.comparisonTolerance
            ? .stable
            : (change < 0 ? .decreased : .increased)
        self.referenceDate = referenceDate
        self.currentDate = currentDate
    }
}

enum InBodyComparisonBaseline: String, Codable, Equatable {
    case previous
    case first
}

struct InBodyComparisonResult: Codable, Equatable {
    let basis: InBodyComparisonBaseline
    let currentSnapshotID: UUID
    let referenceSnapshotID: UUID
    let currentDate: Date
    let referenceDate: Date
    let deltas: [InBodyMetricDelta]

    func delta(for metric: InBodyMetric) -> InBodyMetricDelta? {
        deltas.first { $0.metric == metric }
    }
}

enum InBodyStageStatus: String, Codable, Equatable {
    case insufficientData
    case improving
    case stable
    case mixed
    case attention
}

/// A deterministic description of measured changes. It contains no diagnosis
/// and never infers missing values or the user's emotional state.
struct InBodyStageAnalysis: Codable, Equatable {
    let status: InBodyStageStatus
    let headline: String
    let summary: String
    let highlights: [String]
    let disclaimer: String

    init(
        status: InBodyStageStatus,
        headline: String,
        summary: String,
        highlights: [String] = [],
        disclaimer: String = "仅供身体数据记录参考，不替代医生或营养师的专业判断。"
    ) {
        self.status = status
        self.headline = headline
        self.summary = summary
        self.highlights = highlights
        self.disclaimer = disclaimer
    }
}

/// Provides both useful baselines without forcing views to recalculate dates:
/// the immediately preceding check-in and the first check-in in this stage.
struct InBodyProgressComparison: Equatable {
    let currentSnapshotID: UUID
    let previous: InBodyComparisonResult?
    let first: InBodyComparisonResult?
    let analysis: InBodyStageAnalysis
}
