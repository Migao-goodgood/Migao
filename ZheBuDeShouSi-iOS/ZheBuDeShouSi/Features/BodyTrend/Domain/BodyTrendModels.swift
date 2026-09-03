import Foundation

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
    case ai
    case imported

    var title: String {
        switch self {
        case .manual: return "手动记录"
        case .ocr: return "照片识别"
        case .ai: return "AI 分析"
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
    /// Total body water is reported by InBody in litres. Older app versions
    /// persisted the same numeric value under `bodyWaterKg`; decoding keeps
    /// that legacy key compatible while new snapshots use the correct unit.
    var totalBodyWaterL: Double?
    var proteinKg: Double?
    var mineralKg: Double?
    var fatFreeMassKg: Double?
    var bodyCellMassKg: Double?
    var basalMetabolicRate: Double?
    var smiKgPerM2: Double?
    var targetWeightKg: Double?
    var recommendedCalories: Double?

    /// Segmental lean-mass values in kg, keyed by a stable display key such as
    /// `leftArm`, `rightArm`, `trunk`, `leftLeg`, or `rightLeg`.
    var segmentalMuscleKg: [String: Double]
    /// Segmental fat-mass values in kg using the same stable keys as
    /// `segmentalMuscleKg`.
    var segmentalFatKg: [String: Double]

    var mood: MoodLevel?
    var note: String
    var source: InBodyDataSource
    var deviceModel: String?
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
        totalBodyWaterL: Double? = nil,
        proteinKg: Double? = nil,
        mineralKg: Double? = nil,
        fatFreeMassKg: Double? = nil,
        bodyCellMassKg: Double? = nil,
        basalMetabolicRate: Double? = nil,
        smiKgPerM2: Double? = nil,
        targetWeightKg: Double? = nil,
        recommendedCalories: Double? = nil,
        segmentalMuscleKg: [String: Double] = [:],
        segmentalFatKg: [String: Double] = [:],
        mood: MoodLevel? = nil,
        note: String = "",
        source: InBodyDataSource = .manual,
        deviceModel: String? = nil,
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
        self.totalBodyWaterL = totalBodyWaterL ?? bodyWaterKg
        self.proteinKg = proteinKg
        self.mineralKg = mineralKg
        self.fatFreeMassKg = fatFreeMassKg
        self.bodyCellMassKg = bodyCellMassKg
        self.basalMetabolicRate = basalMetabolicRate
        self.smiKgPerM2 = smiKgPerM2
        self.targetWeightKg = targetWeightKg
        self.recommendedCalories = recommendedCalories
        self.segmentalMuscleKg = segmentalMuscleKg
        self.segmentalFatKg = segmentalFatKg
        self.mood = mood
        self.note = note
        self.source = source
        self.deviceModel = deviceModel
        self.photoReference = photoReference
        self.parserVersion = parserVersion
        self.ocrConfidence = ocrConfidence
    }

    enum CodingKeys: String, CodingKey {
        case id, date, heightCm, age, sex, weightKg, bodyFatKg, bodyFatPercentage
        case skeletalMuscleKg, bmi, visceralFatLevel, score, waistHipRatio
        case totalBodyWaterL, proteinKg, mineralKg, fatFreeMassKg, bodyCellMassKg
        case basalMetabolicRate, smiKgPerM2, targetWeightKg, recommendedCalories
        case segmentalMuscleKg, segmentalFatKg, mood, note, source, deviceModel
        case photoReference, parserVersion, ocrConfidence
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case bodyWaterKg
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
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        totalBodyWaterL = try container.decodeIfPresent(Double.self, forKey: .totalBodyWaterL)
            ?? legacyContainer.decodeIfPresent(Double.self, forKey: .bodyWaterKg)
        proteinKg = try container.decodeIfPresent(Double.self, forKey: .proteinKg)
        mineralKg = try container.decodeIfPresent(Double.self, forKey: .mineralKg)
        fatFreeMassKg = try container.decodeIfPresent(Double.self, forKey: .fatFreeMassKg)
        bodyCellMassKg = try container.decodeIfPresent(Double.self, forKey: .bodyCellMassKg)
        basalMetabolicRate = try container.decodeIfPresent(Double.self, forKey: .basalMetabolicRate)
        smiKgPerM2 = try container.decodeIfPresent(Double.self, forKey: .smiKgPerM2)
        targetWeightKg = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        recommendedCalories = try container.decodeIfPresent(Double.self, forKey: .recommendedCalories)
        segmentalMuscleKg = try container.decodeIfPresent([String: Double].self, forKey: .segmentalMuscleKg) ?? [:]
        segmentalFatKg = try container.decodeIfPresent([String: Double].self, forKey: .segmentalFatKg) ?? [:]
        mood = try container.decodeIfPresent(MoodLevel.self, forKey: .mood)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try container.decodeIfPresent(InBodyDataSource.self, forKey: .source) ?? .manual
        deviceModel = try container.decodeIfPresent(String.self, forKey: .deviceModel)
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
        copy.totalBodyWaterL = rounded(totalBodyWaterL, places: 1)
        copy.proteinKg = rounded(proteinKg, places: 1)
        copy.mineralKg = rounded(mineralKg, places: 2)
        copy.fatFreeMassKg = rounded(fatFreeMassKg, places: 1)
        copy.bodyCellMassKg = rounded(bodyCellMassKg, places: 1)
        copy.basalMetabolicRate = rounded(basalMetabolicRate, places: 0)
        copy.smiKgPerM2 = rounded(smiKgPerM2, places: 1)
        copy.targetWeightKg = rounded(targetWeightKg, places: 1)
        copy.recommendedCalories = rounded(recommendedCalories, places: 0)
        copy.segmentalMuscleKg = segmentalMuscleKg.reduce(into: [:]) { result, item in
            if let value = finite(item.value) { result[item.key] = rounded(value, places: 2) }
        }
        copy.segmentalFatKg = segmentalFatKg.reduce(into: [:]) { result, item in
            if let value = finite(item.value) { result[item.key] = rounded(value, places: 2) }
        }
        copy.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.deviceModel = deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let confidence = finite(ocrConfidence) {
            copy.ocrConfidence = min(1, max(0, confidence))
        } else {
            copy.ocrConfidence = nil
        }
        return copy
    }

    /// Source-compatible alias for code compiled against the original model.
    /// The stored value is a volume in litres, not a mass in kilograms.
    @available(*, deprecated, renamed: "totalBodyWaterL")
    var bodyWaterKg: Double? {
        get { totalBodyWaterL }
        set { totalBodyWaterL = newValue }
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
