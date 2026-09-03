import Foundation

/// Provider-neutral request passed from the diet application flow to a local
/// or remote photo analyzer.
struct DietPhotoAnalysisRequest {
    let date: Date
    let imageData: [Data]
}

/// Review-first analysis output. Missing values are intentional until the
/// user confirms or edits them.
struct DietPhotoAnalysisDraft: Equatable {
    var mealType: DietMealType = .snack
    var title: String = ""
    var caloriesKcal: Int?
    var foods: [RecognizedFoodItem] = []
    var confidence: Double?
    var sourceLabel: String = "设备端识别"

    var isReadyForConfirmation: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || caloriesKcal != nil
    }
}

/// Injectable analyzer boundary. A future GPT/backend adapter can implement
/// this contract without changing the diet page or persistence layer.
typealias DietPhotoAnalysisHandler = (DietPhotoAnalysisRequest) async -> DietPhotoAnalysisDraft?

/// Provider-neutral dietary energy sample passed into the diet store. HealthKit
/// and any future health source are mapped to this value at the application
/// boundary instead of leaking provider types into the diet domain.
struct DietEnergySample: Identifiable, Equatable {
    let id: String
    let date: Date
    let kilocalories: Double
}

/// The meal slot used by the food journal. A snack is intentionally broad so
/// a user can record a small meal without inventing another category.
enum DietMealType: String, Codable, CaseIterable, Identifiable, Hashable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        case .snack: return "加餐"
        }
    }

    var shortTitle: String {
        switch self {
        case .breakfast: return "早"
        case .lunch: return "午"
        case .dinner: return "晚"
        case .snack: return "加"
        }
    }

    /// Stable ordering for a day timeline and the calendar detail sheet.
    var sortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }

    var systemImageName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "sparkles"
        }
    }
}

/// Where the meal entry came from. Photo and AI are separate so the UI can
/// explain whether a value was read from a photo or edited after recognition.
enum DietRecordSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case photo
    case ai
    case healthKit
    case migrated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "手动记录"
        case .photo: return "照片记录"
        case .ai: return "AI 识别"
        case .healthKit: return "Apple 健康"
        case .migrated: return "历史记录"
        }
    }
}

/// Recognition is review-first: a prediction is never presented as verified
/// until the user has had a chance to edit and save it.
enum DietRecognitionStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case pending
    case recognized
    case needsReview
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: return "未识别"
        case .pending: return "识别中"
        case .recognized: return "已识别"
        case .needsReview: return "待确认"
        case .failed: return "识别失败"
        }
    }

    var isPending: Bool { self == .pending }
}

/// One item returned by a food-recognition service. Nutritional fields are
/// optional because a model may identify a food without a reliable estimate.
struct RecognizedFoodItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var caloriesKcal: Double?
    var confidence: Double?
    var servingDescription: String?

    init(
        id: UUID = UUID(),
        name: String,
        caloriesKcal: Double? = nil,
        confidence: Double? = nil,
        servingDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.caloriesKcal = caloriesKcal
        self.confidence = confidence
        self.servingDescription = servingDescription
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, caloriesKcal, confidence, servingDescription
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case calories, serving, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? legacy.decodeIfPresent(String.self, forKey: .title)
            ?? ""
        caloriesKcal = try container.decodeIfPresent(Double.self, forKey: .caloriesKcal)
            ?? legacy.decodeIfPresent(Double.self, forKey: .calories)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        servingDescription = try container.decodeIfPresent(String.self, forKey: .servingDescription)
            ?? legacy.decodeIfPresent(String.self, forKey: .serving)
    }

    func normalized() -> RecognizedFoodItem {
        var copy = self
        copy.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        copy.caloriesKcal = roundedFinite(caloriesKcal, places: 1)
        copy.confidence = confidence.map { min(1, max(0, $0)) }
        copy.servingDescription = servingDescription.map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        }
        return copy
    }

    private func roundedFinite(_ value: Double?, places: Int) -> Double? {
        guard let value, value.isFinite else { return nil }
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}

/// Metadata and bytes for one report/meal photo.
///
/// `imageData` is deliberately optional. The first implementation stores
/// compressed bytes directly for immediate SwiftUI rendering; a future file
/// store can instead persist `storageIdentifier` and leave bytes nil. Keeping
/// both fields avoids coupling the domain model to UIKit or Photos.
struct MealImageMetadata: Identifiable, Codable, Equatable, Hashable {
    static let maxImageBytes = 5_000_000

    var id: UUID
    var imageData: Data?
    var storageIdentifier: String?
    var filename: String?
    var mimeType: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var capturedAt: Date?
    var altText: String?

    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        storageIdentifier: String? = nil,
        filename: String? = nil,
        mimeType: String = "image/jpeg",
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        capturedAt: Date? = nil,
        altText: String? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.storageIdentifier = storageIdentifier
        self.filename = filename
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.capturedAt = capturedAt
        self.altText = altText
    }

    /// Convenience label for PhotosPicker/Data callers. The longer
    /// `imageData:` initializer remains useful when several optional fields
    /// are supplied together.
    init(
        data: Data,
        filename: String? = nil,
        mimeType: String = "image/jpeg",
        id: UUID = UUID(),
        capturedAt: Date? = nil,
        altText: String? = nil
    ) {
        self.init(
            id: id,
            imageData: data,
            filename: filename,
            mimeType: mimeType,
            capturedAt: capturedAt,
            altText: altText
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, imageData, storageIdentifier, filename, mimeType
        case pixelWidth, pixelHeight, capturedAt, altText
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case data, path, url, name, type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
            ?? legacy.decodeIfPresent(Data.self, forKey: .data)
        storageIdentifier = try container.decodeIfPresent(String.self, forKey: .storageIdentifier)
            ?? legacy.decodeIfPresent(String.self, forKey: .path)
            ?? legacy.decodeIfPresent(String.self, forKey: .url)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
            ?? legacy.decodeIfPresent(String.self, forKey: .name)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? legacy.decodeIfPresent(String.self, forKey: .type)
            ?? "image/jpeg"
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
        altText = try container.decodeIfPresent(String.self, forKey: .altText)
    }

    var byteCount: Int { imageData?.count ?? 0 }

    /// True when the UI has something it can render or hand to a file loader.
    /// Empty Data is treated as missing so a failed PhotosPicker transfer does
    /// not create a phantom image tile.
    var isDisplayable: Bool { imageData?.isEmpty == false || storageIdentifier != nil }

    func normalized() -> MealImageMetadata {
        var copy = self
        copy.storageIdentifier = cleaned(storageIdentifier, limit: 240)
        copy.filename = cleaned(filename, limit: 180)
        copy.mimeType = String(mimeType.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if copy.mimeType.isEmpty { copy.mimeType = "image/jpeg" }
        copy.pixelWidth = pixelWidth.flatMap { $0 > 0 ? min($0, 100_000) : nil }
        copy.pixelHeight = pixelHeight.flatMap { $0 > 0 ? min($0, 100_000) : nil }
        copy.altText = cleaned(altText, limit: 240)
        return copy
    }

    var isWithinStorageLimit: Bool {
        guard isDisplayable else { return false }
        return byteCount <= Self.maxImageBytes
    }

    private func cleaned(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let result = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        return result.isEmpty ? nil : result
    }
}

/// A single meal journal entry. A record can be image-only while recognition
/// is pending; calories become optional until the user confirms a value.
struct MealRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var mealType: DietMealType
    var title: String
    var caloriesKcal: Double?
    var images: [MealImageMetadata]
    var foods: [RecognizedFoodItem]
    var recognitionStatus: DietRecognitionStatus
    var recognitionMessage: String?
    var note: String
    var source: DietRecordSource
    /// HealthKit sample identifiers make repeated syncs idempotent. Manual
    /// and photo entries leave this nil.
    var externalIdentifier: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        mealType: DietMealType = .snack,
        title: String = "",
        caloriesKcal: Double? = nil,
        images: [MealImageMetadata] = [],
        foods: [RecognizedFoodItem] = [],
        recognitionStatus: DietRecognitionStatus = .notStarted,
        recognitionMessage: String? = nil,
        note: String = "",
        source: DietRecordSource = .manual,
        externalIdentifier: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.mealType = mealType
        self.title = title
        self.caloriesKcal = caloriesKcal
        self.images = images
        self.foods = foods
        self.recognitionStatus = recognitionStatus
        self.recognitionMessage = recognitionMessage
        self.note = note
        self.source = source
        self.externalIdentifier = externalIdentifier
        let created = createdAt ?? date
        self.createdAt = created
        self.updatedAt = updatedAt ?? created
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, mealType, title, caloriesKcal, images, foods
        case recognitionStatus, recognitionMessage, note, source, externalIdentifier
        case createdAt, updatedAt
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case name, calories, meal, mealKind, foodItems, imageData, photoData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .now

        let rawMealType = try container.decodeIfPresent(DietMealType.self, forKey: .mealType)
            ?? legacy.decodeIfPresent(DietMealType.self, forKey: .meal)
        let rawMealKind = try legacy.decodeIfPresent(String.self, forKey: .mealKind)
        mealType = rawMealType
            ?? rawMealKind.flatMap(DietMealType.init(rawValue:))
            ?? .snack

        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? legacy.decodeIfPresent(String.self, forKey: .name)
            ?? ""
        caloriesKcal = try container.decodeIfPresent(Double.self, forKey: .caloriesKcal)
            ?? legacy.decodeIfPresent(Double.self, forKey: .calories)
        images = try container.decodeIfPresent([MealImageMetadata].self, forKey: .images) ?? []
        if images.isEmpty {
            if let data = try legacy.decodeIfPresent(Data.self, forKey: .imageData)
                ?? legacy.decodeIfPresent(Data.self, forKey: .photoData) {
                images = [MealImageMetadata(data: data)]
            }
        }
        foods = try container.decodeIfPresent([RecognizedFoodItem].self, forKey: .foods)
            ?? legacy.decodeIfPresent([RecognizedFoodItem].self, forKey: .foodItems)
            ?? []
        recognitionStatus = try container.decodeIfPresent(DietRecognitionStatus.self, forKey: .recognitionStatus)
            ?? (images.isEmpty ? .notStarted : .needsReview)
        recognitionMessage = try container.decodeIfPresent(String.self, forKey: .recognitionMessage)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try container.decodeIfPresent(DietRecordSource.self, forKey: .source) ?? .manual
        externalIdentifier = try container.decodeIfPresent(String.self, forKey: .externalIdentifier)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    /// Compatibility aliases keep the view layer readable and allow an older
    /// prototype that called these fields `name`/`calories` to migrate easily.
    var name: String {
        get { title }
        set { title = newValue }
    }

    var calories: Double? {
        get { caloriesKcal }
        set { caloriesKcal = newValue }
    }

    var calculatedCaloriesKcal: Double? {
        if let caloriesKcal { return caloriesKcal }
        let values = foods.compactMap(\.caloriesKcal)
        guard !values.isEmpty, values.count == foods.count else { return nil }
        return values.reduce(0, +)
    }

    var imageCount: Int { images.count }

    /// Convenient projection for SwiftUI collage views that only need bytes.
    var imageData: [Data] { images.compactMap(\.imageData).filter { !$0.isEmpty } }

    var primaryImageData: Data? { imageData.first }

    func normalized() -> MealRecord {
        var copy = self
        copy.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        copy.caloriesKcal = roundedFinite(caloriesKcal, places: 1)
        copy.images = Array(images.map { $0.normalized() }.filter { $0.isWithinStorageLimit }.prefix(6))
        copy.foods = Array(foods.map { $0.normalized() }.filter { !$0.name.isEmpty }.prefix(40))
        copy.recognitionMessage = cleaned(recognitionMessage, limit: 240)
        copy.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
        copy.externalIdentifier = cleaned(externalIdentifier, limit: 240)
        copy.createdAt = createdAt.isFiniteDate ? createdAt : date
        copy.updatedAt = updatedAt.isFiniteDate ? updatedAt : copy.createdAt
        return copy
    }

    private func roundedFinite(_ value: Double?, places: Int) -> Double? {
        guard let value, value.isFinite else { return nil }
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    private func cleaned(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let result = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        return result.isEmpty ? nil : result
    }
}

/// Read-only projection used by the calendar. It is derived from meal records
/// and is never persisted separately, so totals cannot drift from their source.
struct DietDaySummary: Identifiable, Equatable {
    let date: Date
    let totalCaloriesKcal: Double
    let mealCount: Int
    let imageCount: Int
    let pendingRecognitionCount: Int
    let records: [MealRecord]

    var id: Date { date }
    var caloriesKcal: Double { totalCaloriesKcal }
    var hasMeals: Bool { mealCount > 0 }
    var hasImages: Bool { imageCount > 0 }
    var hasPendingRecognition: Bool { pendingRecognitionCount > 0 }

    init(
        date: Date,
        totalCaloriesKcal: Double = 0,
        mealCount: Int = 0,
        imageCount: Int = 0,
        pendingRecognitionCount: Int = 0,
        records: [MealRecord] = []
    ) {
        self.date = date
        self.totalCaloriesKcal = totalCaloriesKcal
        self.mealCount = mealCount
        self.imageCount = imageCount
        self.pendingRecognitionCount = pendingRecognitionCount
        self.records = records
    }
}

/// Naming aliases for callers that prefer a domain-oriented vocabulary.
typealias DietMeal = MealRecord
typealias DailyDietSummary = DietDaySummary

private extension Date {
    /// Date is a value type, but this guards against malformed persisted
    /// timestamps on platforms that can decode non-finite reference values.
    var isFiniteDate: Bool {
        timeIntervalSinceReferenceDate.isFinite
    }
}
