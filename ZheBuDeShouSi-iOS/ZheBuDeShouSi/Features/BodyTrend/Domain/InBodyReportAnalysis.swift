import Foundation

/// The provider that produced an InBody report analysis.
///
/// `remoteAI` is intentionally an app-level label only. The app talks to a
/// configurable backend endpoint; provider credentials and model keys must
/// remain on that backend and are never bundled in the client.
enum InBodyAnalysisProvider: String, Codable, Sendable {
    case localOCR
    case remoteAI
}

/// A reviewable analysis result shared by local OCR and an optional AI backend.
/// Every field is optional because a report can be cropped, incomplete, or
/// unreadable. The review screen remains the authority before persistence.
struct InBodyReportAnalysis: Codable, Equatable, Sendable {
    var measurementDate: Date?
    var heightCm: Double?
    var age: Int?
    var sex: String?
    var deviceModel: String?

    var weightKg: Double?
    var bodyFatKg: Double?
    var bodyFatPercent: Double?
    var skeletalMuscleKg: Double?
    var visceralFatLevel: Double?
    var bmi: Double?
    var score: Int?

    var waistHipRatio: Double?
    var totalBodyWaterL: Double?
    var proteinKg: Double?
    var mineralKg: Double?
    var fatFreeMassKg: Double?
    var bodyCellMassKg: Double?
    var basalMetabolicRate: Double?
    var smiKgPerM2: Double?

    var recognizedText: String
    /// Number of recognized values among the original six primary fields.
    /// Keeping this definition stable preserves existing review UI behavior.
    var matchedFieldCount: Int
    var provider: InBodyAnalysisProvider
    var confidence: Double?
    var parserVersion: String
    var message: String?

    init(
        measurementDate: Date? = nil,
        heightCm: Double? = nil,
        age: Int? = nil,
        sex: String? = nil,
        deviceModel: String? = nil,
        weightKg: Double? = nil,
        bodyFatKg: Double? = nil,
        bodyFatPercent: Double? = nil,
        skeletalMuscleKg: Double? = nil,
        visceralFatLevel: Double? = nil,
        bmi: Double? = nil,
        score: Int? = nil,
        waistHipRatio: Double? = nil,
        totalBodyWaterL: Double? = nil,
        proteinKg: Double? = nil,
        mineralKg: Double? = nil,
        fatFreeMassKg: Double? = nil,
        bodyCellMassKg: Double? = nil,
        basalMetabolicRate: Double? = nil,
        smiKgPerM2: Double? = nil,
        recognizedText: String = "",
        matchedFieldCount: Int = 0,
        provider: InBodyAnalysisProvider = .localOCR,
        confidence: Double? = nil,
        parserVersion: String = "vision-1",
        message: String? = nil
    ) {
        self.measurementDate = measurementDate
        self.heightCm = heightCm
        self.age = age
        self.sex = sex
        self.deviceModel = deviceModel
        self.weightKg = weightKg
        self.bodyFatKg = bodyFatKg
        self.bodyFatPercent = bodyFatPercent
        self.skeletalMuscleKg = skeletalMuscleKg
        self.visceralFatLevel = visceralFatLevel
        self.bmi = bmi
        self.score = score
        self.waistHipRatio = waistHipRatio
        self.totalBodyWaterL = totalBodyWaterL
        self.proteinKg = proteinKg
        self.mineralKg = mineralKg
        self.fatFreeMassKg = fatFreeMassKg
        self.bodyCellMassKg = bodyCellMassKg
        self.basalMetabolicRate = basalMetabolicRate
        self.smiKgPerM2 = smiKgPerM2
        self.recognizedText = recognizedText
        self.matchedFieldCount = matchedFieldCount
        self.provider = provider
        self.confidence = confidence
        self.parserVersion = parserVersion
        self.message = message
    }

    /// The persisted source label used by `InBodySnapshot`.
    var dataSource: InBodyDataSource {
        provider == .remoteAI ? .ai : .ocr
    }

    /// The fraction of the six primary fields that were found.
    var completionRatio: Double {
        min(1, max(0, Double(matchedFieldCount) / 6))
    }

    /// Total number of report values available for review, including profile
    /// metadata and the extended body-composition fields.
    var recognizedFieldCount: Int {
        let values: [Bool] = [
            measurementDate != nil,
            heightCm != nil,
            age != nil,
            !(sex?.isEmpty ?? true),
            !(deviceModel?.isEmpty ?? true),
            weightKg != nil,
            bodyFatKg != nil,
            bodyFatPercent != nil,
            skeletalMuscleKg != nil,
            visceralFatLevel != nil,
            bmi != nil,
            score != nil,
            waistHipRatio != nil,
            totalBodyWaterL != nil,
            proteinKg != nil,
            mineralKg != nil,
            fatFreeMassKg != nil,
            bodyCellMassKg != nil,
            basalMetabolicRate != nil,
            smiKgPerM2 != nil
        ]
        return values.filter { $0 }.count
    }
}

/// Application-facing seam for report analysis. Implementations can be
/// swapped in previews/tests or replaced with a product backend without
/// changing the SwiftUI presentation.
protocol InBodyReportAnalyzing: Sendable {
    func analyze(data: Data) async -> InBodyReportAnalysis
}
