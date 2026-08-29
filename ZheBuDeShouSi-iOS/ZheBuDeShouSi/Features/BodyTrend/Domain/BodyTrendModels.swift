import Foundation

/// The visual subject used by the body-trend preview.
enum AvatarStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case helloKitty
    case human
    case cat
    case dog
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .helloKitty: return "Hello Kitty"
        case .human: return "人物"
        case .cat: return "小猫"
        case .dog: return "小狗"
        case .custom: return "我的形象"
        }
    }

    var symbolName: String {
        switch self {
        case .helloKitty: return "sparkles"
        case .human: return "figure.stand"
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .custom: return "photo.fill"
        }
    }
}

/// A self-reported mood attached to an InBody check-in. InBody does not
/// contain emotional data, so this value is intentionally explicit and optional.
enum MoodLevel: Int, Codable, CaseIterable, Identifiable {
    case veryLow = 1
    case low = 2
    case neutral = 3
    case good = 4
    case excellent = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .veryLow: return "有点低落"
        case .low: return "不太好"
        case .neutral: return "平平稳稳"
        case .good: return "状态不错"
        case .excellent: return "元气满满"
        }
    }

    var emoji: String {
        switch self {
        case .veryLow: return "😔"
        case .low: return "😕"
        case .neutral: return "😌"
        case .good: return "🙂"
        case .excellent: return "✨"
        }
    }
}

enum InBodyDataSource: String, Codable, CaseIterable {
    case manual
    case ocr
    case imported

    var title: String {
        switch self {
        case .manual: return "手动录入"
        case .ocr: return "照片识别"
        case .imported: return "导入"
        }
    }
}

/// A verified (or user-edited) snapshot from one InBody check-in.
///
/// Most numeric values are optional because OCR may not find every field. The
/// review screen can save a partial snapshot as long as a valid weight exists;
/// the evaluator reports missing data instead of guessing.
struct InBodySnapshot: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date

    var heightCm: Double?
    var age: Int?
    var sex: String?

    var weightKg: Double?
    var bodyFatKg: Double?
    var bodyFatPercentage: Double?
    var skeletalMuscleKg: Double?
    var bmi: Double?
    var visceralFatLevel: Double?
    var score: Double?

    var waistHipRatio: Double?
    var bodyWaterKg: Double?
    var proteinKg: Double?
    var mineralKg: Double?
    var fatFreeMassKg: Double?
    var basalMetabolicRate: Double?
    var targetWeightKg: Double?
    var recommendedCalories: Double?

    /// Segmental lean-mass values in kg, keyed by a stable display key such as
    /// `leftArm`, `rightArm`, `trunk`, `leftLeg`, or `rightLeg`.
    var segmentalMuscleKg: [String: Double]

    var mood: MoodLevel?
    var note: String
    var source: InBodyDataSource
    /// A relative path or opaque identifier managed by the photo store. The
    /// full report image is deliberately not embedded in this model.
    var photoReference: String?
    var parserVersion: String?
    var ocrConfidence: Double?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        heightCm: Double? = nil,
        age: Int? = nil,
        sex: String? = nil,
        weightKg: Double? = nil,
        bodyFatKg: Double? = nil,
        bodyFatPercentage: Double? = nil,
        skeletalMuscleKg: Double? = nil,
        bmi: Double? = nil,
        visceralFatLevel: Double? = nil,
        score: Double? = nil,
        waistHipRatio: Double? = nil,
        bodyWaterKg: Double? = nil,
        proteinKg: Double? = nil,
        mineralKg: Double? = nil,
        fatFreeMassKg: Double? = nil,
        basalMetabolicRate: Double? = nil,
        targetWeightKg: Double? = nil,
        recommendedCalories: Double? = nil,
        segmentalMuscleKg: [String: Double] = [:],
        mood: MoodLevel? = nil,
        note: String = "",
        source: InBodyDataSource = .manual,
        photoReference: String? = nil,
        parserVersion: String? = nil,
        ocrConfidence: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.heightCm = heightCm
        self.age = age
        self.sex = sex
        self.weightKg = weightKg
        self.bodyFatKg = bodyFatKg
        self.bodyFatPercentage = bodyFatPercentage
        self.skeletalMuscleKg = skeletalMuscleKg
        self.bmi = bmi
        self.visceralFatLevel = visceralFatLevel
        self.score = score
        self.waistHipRatio = waistHipRatio
        self.bodyWaterKg = bodyWaterKg
        self.proteinKg = proteinKg
        self.mineralKg = mineralKg
        self.fatFreeMassKg = fatFreeMassKg
        self.basalMetabolicRate = basalMetabolicRate
        self.targetWeightKg = targetWeightKg
        self.recommendedCalories = recommendedCalories
        self.segmentalMuscleKg = segmentalMuscleKg
        self.mood = mood
        self.note = note
        self.source = source
        self.photoReference = photoReference
        self.parserVersion = parserVersion
        self.ocrConfidence = ocrConfidence
    }

    enum CodingKeys: String, CodingKey {
        case id, date, heightCm, age, sex, weightKg, bodyFatKg, bodyFatPercentage
        case skeletalMuscleKg, bmi, visceralFatLevel, score, waistHipRatio
        case bodyWaterKg, proteinKg, mineralKg, fatFreeMassKg, basalMetabolicRate
        case targetWeightKg, recommendedCalories, segmentalMuscleKg, mood, note
        case source, photoReference, parserVersion, ocrConfidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .now
        heightCm = try container.decodeIfPresent(Double.self, forKey: .heightCm)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        sex = try container.decodeIfPresent(String.self, forKey: .sex)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        bodyFatKg = try container.decodeIfPresent(Double.self, forKey: .bodyFatKg)
        bodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercentage)
        skeletalMuscleKg = try container.decodeIfPresent(Double.self, forKey: .skeletalMuscleKg)
        bmi = try container.decodeIfPresent(Double.self, forKey: .bmi)
        visceralFatLevel = try container.decodeIfPresent(Double.self, forKey: .visceralFatLevel)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        waistHipRatio = try container.decodeIfPresent(Double.self, forKey: .waistHipRatio)
        bodyWaterKg = try container.decodeIfPresent(Double.self, forKey: .bodyWaterKg)
        proteinKg = try container.decodeIfPresent(Double.self, forKey: .proteinKg)
        mineralKg = try container.decodeIfPresent(Double.self, forKey: .mineralKg)
        fatFreeMassKg = try container.decodeIfPresent(Double.self, forKey: .fatFreeMassKg)
        basalMetabolicRate = try container.decodeIfPresent(Double.self, forKey: .basalMetabolicRate)
        targetWeightKg = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        recommendedCalories = try container.decodeIfPresent(Double.self, forKey: .recommendedCalories)
        segmentalMuscleKg = try container.decodeIfPresent([String: Double].self, forKey: .segmentalMuscleKg) ?? [:]
        mood = try container.decodeIfPresent(MoodLevel.self, forKey: .mood)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try container.decodeIfPresent(InBodyDataSource.self, forKey: .source) ?? .manual
        photoReference = try container.decodeIfPresent(String.self, forKey: .photoReference)
        parserVersion = try container.decodeIfPresent(String.self, forKey: .parserVersion)
        ocrConfidence = try container.decodeIfPresent(Double.self, forKey: .ocrConfidence)
    }

    var hasWeight: Bool { valid(weightKg, in: 20...400) }

    var completeness: Double {
        let values: [Double?] = [weightKg, bodyFatPercentage, skeletalMuscleKg, bmi, visceralFatLevel, score]
        return Double(values.compactMap { $0 }.count) / Double(values.count)
    }

    /// Returns a copy with finite values rounded for stable display/persistence.
    func normalized() -> InBodySnapshot {
        var copy = self
        copy.heightCm = rounded(heightCm, places: 1)
        copy.weightKg = rounded(weightKg, places: 1)
        copy.bodyFatKg = rounded(bodyFatKg, places: 1)
        copy.bodyFatPercentage = rounded(bodyFatPercentage, places: 1)
        copy.skeletalMuscleKg = rounded(skeletalMuscleKg, places: 1)
        copy.bmi = rounded(bmi, places: 1)
        copy.visceralFatLevel = rounded(visceralFatLevel, places: 1)
        copy.score = rounded(score, places: 1)
        copy.waistHipRatio = rounded(waistHipRatio, places: 2)
        copy.bodyWaterKg = rounded(bodyWaterKg, places: 1)
        copy.proteinKg = rounded(proteinKg, places: 1)
        copy.mineralKg = rounded(mineralKg, places: 2)
        copy.fatFreeMassKg = rounded(fatFreeMassKg, places: 1)
        copy.basalMetabolicRate = rounded(basalMetabolicRate, places: 0)
        copy.targetWeightKg = rounded(targetWeightKg, places: 1)
        copy.recommendedCalories = rounded(recommendedCalories, places: 0)
        copy.segmentalMuscleKg = segmentalMuscleKg.reduce(into: [:]) { result, item in
            if let value = finite(item.value) { result[item.key] = rounded(value, places: 2) }
        }
        copy.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let confidence = finite(ocrConfidence) {
            copy.ocrConfidence = min(1, max(0, confidence))
        } else {
            copy.ocrConfidence = nil
        }
        return copy
    }

    private func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        guard let value, value.isFinite else { return false }
        return range.contains(value)
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private func rounded(_ value: Double?, places: Int) -> Double? {
        guard let value = finite(value) else { return nil }
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}

struct AvatarParameters: Equatable {
    var torsoScale: Double = 1
    var waistScale: Double = 1
    var hipScale: Double = 1
    var limbScale: Double = 1
    var fullness: Double = 0.5

    static let neutral = AvatarParameters()
}

extension InBodySnapshot {
    /// Maps measured changes to restrained visual parameters for a stylized
    /// avatar. It is intentionally not a medical or photographic reconstruction.
    func avatarParameters(relativeTo previous: InBodySnapshot? = nil) -> AvatarParameters {
        let fat = min(1, max(0, ((bodyFatPercentage ?? 25) - 8) / 42))
        let muscle = min(1.2, max(0.75, (skeletalMuscleKg ?? 20) / 20))
        let change: Double? = previous.flatMap { old in
            guard let current = self.weightKg, let oldWeight = old.weightKg, oldWeight > 0 else { return nil }
            return current / oldWeight
        }
        let weightScale = min(1.15, max(0.85, change ?? 1))
        return AvatarParameters(
            torsoScale: weightScale * (0.94 + fat * 0.12),
            waistScale: weightScale * (0.88 + fat * 0.22),
            hipScale: weightScale * (0.92 + fat * 0.16),
            limbScale: min(1.12, max(0.88, 0.9 + muscle * 0.1)),
            fullness: fat
        )
    }
}

enum BodyTrendAssessmentStatus: String, Codable, CaseIterable {
    case insufficientData
    case improving
    case stable
    case attention

    var title: String {
        switch self {
        case .insufficientData: return "继续补充数据"
        case .improving: return "趋势向好"
        case .stable: return "保持稳定"
        case .attention: return "值得留意"
        }
    }
}

struct BodyTrendAssessment: Codable, Equatable, Identifiable {
    var id: UUID
    var snapshotID: UUID
    var previousSnapshotID: UUID?
    var status: BodyTrendAssessmentStatus
    var headline: String
    var summary: String
    var highlights: [String]
    var recommendations: [String]
    var disclaimer: String
    var generatedAt: Date
    var ruleVersion: String

    init(
        id: UUID = UUID(),
        snapshotID: UUID,
        previousSnapshotID: UUID? = nil,
        status: BodyTrendAssessmentStatus,
        headline: String,
        summary: String,
        highlights: [String] = [],
        recommendations: [String] = [],
        disclaimer: String = "仅供健康记录参考，不替代医生的专业诊断。",
        generatedAt: Date = .now,
        ruleVersion: String = "1"
    ) {
        self.id = id
        self.snapshotID = snapshotID
        self.previousSnapshotID = previousSnapshotID
        self.status = status
        self.headline = headline
        self.summary = summary
        self.highlights = highlights
        self.recommendations = recommendations
        self.disclaimer = disclaimer
        self.generatedAt = generatedAt
        self.ruleVersion = ruleVersion
    }

    var detail: String { summary }
    var bullets: [String] { highlights }
}

/// Deterministic, offline evaluation. It describes trends and missing fields;
/// it does not infer a diagnosis or a user's emotional state.
enum BodyTrendEvaluator {
    static func evaluate(snapshot: InBodySnapshot, previous: InBodySnapshot? = nil) -> BodyTrendAssessment {
        let current = snapshot.normalized()
        var highlights: [String] = []
        var recommendations: [String] = []
        var cautions = 0

        guard let weight = current.weightKg, weight.isFinite else {
            return BodyTrendAssessment(
                snapshotID: current.id,
                previousSnapshotID: previous?.id,
                status: .insufficientData,
                headline: "先补充体重",
                summary: "这条记录缺少有效体重，补充后才能生成趋势评价。"
            )
        }

        if let bmi = current.bmi {
            if bmi < 18.5 {
                cautions += 1
                highlights.append("BMI \(format(bmi, places: 1))，偏低区间")
                recommendations.append("优先保证规律饮食和充足休息，不必追求更快下降。")
            } else if bmi < 24 {
                highlights.append("BMI \(format(bmi, places: 1))，处于常用参考区间")
            } else {
                cautions += 1
                highlights.append("BMI \(format(bmi, places: 1))，可结合体脂和肌肉一起观察")
                recommendations.append("把变化看成长线趋势，配合稳定运动和饮食记录。")
            }
        }

        if let visceral = current.visceralFatLevel, visceral >= 10 {
            cautions += 1
            highlights.append("内脏脂肪等级 \(format(visceral, places: 0))，建议继续关注后续变化")
        }

        if let score = current.score {
            if score >= 80 {
                highlights.append("InBody 评分 \(format(score, places: 0))，状态不错")
            } else if score < 70 {
                cautions += 1
                highlights.append("InBody 评分 \(format(score, places: 0))，建议结合多次记录观察")
            }
        }

        if let previous,
           let oldWeight = previous.weightKg,
           oldWeight.isFinite {
            let delta = weight - oldWeight
            if abs(delta) >= 0.1 {
                let direction = delta < 0 ? "下降" : "上升"
                highlights.append("较上次\(direction) \(format(abs(delta), places: 1)) kg")
            } else {
                highlights.append("体重与上次基本持平")
            }

            if let fat = current.bodyFatPercentage,
               let oldFat = previous.bodyFatPercentage {
                let fatDelta = fat - oldFat
                if fatDelta < -0.2 {
                    highlights.append("体脂率下降 \(format(abs(fatDelta), places: 1)) 个百分点")
                } else if fatDelta > 0.8 {
                    cautions += 1
                    highlights.append("体脂率较上次上升 \(format(fatDelta, places: 1)) 个百分点")
                }
            }

            if let muscle = current.skeletalMuscleKg,
               let oldMuscle = previous.skeletalMuscleKg,
               muscle - oldMuscle >= 0.2 {
                highlights.append("骨骼肌增加 \(format(muscle - oldMuscle, places: 1)) kg")
            }
        }

        if current.mood == nil {
            recommendations.append("下次测量时顺手记一下心情，时间线会更完整。")
        }
        if highlights.isEmpty {
            highlights.append("已记录体重 \(format(weight, places: 1)) kg")
        }
        if recommendations.isEmpty {
            recommendations.append("保持相近时间测量，连续记录比单次数字更有参考价值。")
        }

        let status: BodyTrendAssessmentStatus
        if cautions > 0 {
            status = .attention
        } else if highlights.contains(where: { $0.contains("下降") || $0.contains("增加") }) {
            status = .improving
        } else {
            status = .stable
        }
        let summary = "本次记录 \(format(weight, places: 1)) kg。评价基于已填写的 InBody 指标和相邻记录，缺失项目不会被推测。"
        return BodyTrendAssessment(
            snapshotID: current.id,
            previousSnapshotID: previous?.id,
            status: status,
            headline: status.title,
            summary: summary,
            highlights: highlights,
            recommendations: recommendations
        )
    }

    private static func format(_ value: Double, places: Int) -> String {
        String(format: "%.*f", places, value)
    }
}
