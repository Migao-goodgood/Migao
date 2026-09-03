import Foundation
import Combine

/// Owns food-journal state and its local persistence boundary. SwiftUI views
/// should query this store and send mutations through its methods; they should
/// not write UserDefaults or calculate calendar totals themselves.
@MainActor
final class DietStore: ObservableObject {
    static let storageKey = "zhebudeshousi.dietStore.v1"

    /// The old app kept meal entries inside AppState.logs. This marker makes
    /// migration idempotent even when the store is recreated several times.
    private static let legacyMigrationKey = "zhebudeshousi.dietStore.legacyMigration.v1"
    private static let legacyAppStateKey = "zhebudeshousi.appState"

    static let maxMeals = 2_000
    static let maxImagesPerMeal = 6
    /// UserDefaults is a convenient MVP boundary, but it is not a photo
    /// library. Keep the aggregate image payload bounded until a file-backed
    /// store is introduced.
    static let maxTotalImageBytes = 16_000_000
    static let maxPersistedPayloadBytes = 24_000_000

    @Published private(set) var meals: [MealRecord] = []

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        migrateLegacy: Bool = true
    ) {
        self.defaults = defaults
        var normalizedCalendar = calendar
        normalizedCalendar.locale = calendar.locale ?? Locale(identifier: "zh_CN")
        self.calendar = normalizedCalendar
        load()

        if migrateLegacy {
            migrateLegacyActivityLogsIfNeeded()
        }
    }

    var latest: MealRecord? { meals.first }

    var totalImageBytes: Int {
        meals.reduce(0) { partial, meal in
            partial + meal.images.reduce(0) { $0 + $1.byteCount }
        }
    }

    /// Returns the start of the user's local calendar day.
    func dayStart(for date: Date) -> Date { calendar.startOfDay(for: date) }

    /// Meals for one local day, ordered by meal slot and then capture time.
    func records(on date: Date) -> [MealRecord] {
        let day = calendar.startOfDay(for: date)
        return meals
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { lhs, rhs in
                if lhs.mealType.sortOrder != rhs.mealType.sortOrder {
                    return lhs.mealType.sortOrder < rhs.mealType.sortOrder
                }
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Alias used by calendar-oriented callers.
    func meals(on date: Date) -> [MealRecord] { records(on: date) }

    func record(id: UUID) -> MealRecord? {
        meals.first { $0.id == id }
    }

    /// Returns records in the month containing `date`, newest day first.
    func records(inMonth date: Date) -> [MealRecord] {
        meals
            .filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    /// Calendar projection. Only days with a record are returned; callers can
    /// still ask `summary(for:)` for an empty day without creating state.
    func summaries(inMonth date: Date) -> [DietDaySummary] {
        let grouped = Dictionary(grouping: records(inMonth: date)) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            makeSummary(for: day, records: grouped[day] ?? [])
        }
    }

    /// Alias for code that calls the projection a daily summary list.
    func dailySummaries(inMonth date: Date) -> [DietDaySummary] {
        summaries(inMonth: date)
    }

    func summary(for date: Date) -> DietDaySummary {
        makeSummary(for: calendar.startOfDay(for: date), records: records(on: date))
    }

    func totalCalories(on date: Date) -> Double {
        summary(for: date).totalCaloriesKcal
    }

    /// Adds a new record. IDs are intentionally unique; use `upsert` for edit
    /// flows so accidental duplicate submissions cannot create two tiles.
    @discardableResult
    func add(_ record: MealRecord) -> Bool {
        guard meals.allSatisfy({ $0.id != record.id }) else { return false }
        guard let cleaned = validated(record), meals.count < Self.maxMeals else { return false }
        guard canStoreAdditionalImages(cleaned.images) else { return false }
        meals.append(cleaned)
        sortAndSave()
        return true
    }

    /// Inserts or replaces a record by ID.
    @discardableResult
    func upsert(_ record: MealRecord) -> Bool {
        guard let cleaned = validated(record) else { return false }
        let existingImageBytes = meals.first(where: { $0.id == cleaned.id })?.images.reduce(0) { $0 + $1.byteCount } ?? 0
        let newImageBytes = cleaned.images.reduce(0) { $0 + $1.byteCount }
        guard totalImageBytes - existingImageBytes + newImageBytes <= Self.maxTotalImageBytes else {
            return false
        }

        if let index = meals.firstIndex(where: { $0.id == cleaned.id }) {
            meals[index] = cleaned
        } else {
            guard meals.count < Self.maxMeals else { return false }
            meals.append(cleaned)
        }
        sortAndSave()
        return true
    }

    /// Alias for edit screens.
    @discardableResult
    func update(_ record: MealRecord) -> Bool { upsert(record) }

    /// Convenience constructor used by upload/manual-entry UI.
    @discardableResult
    func addMeal(
        date: Date = .now,
        mealType: DietMealType = .snack,
        title: String = "",
        caloriesKcal: Double? = nil,
        images: [MealImageMetadata] = [],
        note: String = "",
        source: DietRecordSource = .manual,
        recognitionStatus: DietRecognitionStatus = .notStarted,
        foods: [RecognizedFoodItem] = [],
        recognitionMessage: String? = nil
    ) -> MealRecord? {
        let record = MealRecord(
            date: date,
            mealType: mealType,
            title: title,
            caloriesKcal: caloriesKcal,
            images: images,
            foods: foods,
            recognitionStatus: recognitionStatus,
            recognitionMessage: recognitionMessage,
            note: note,
            source: source
        )
        return add(record) ? meals.first(where: { $0.id == record.id }) : nil
    }

    /// Updates only the recognition result while preserving user-entered
    /// title, note, images, and timestamps.
    @discardableResult
    func updateRecognition(
        for id: UUID,
        status: DietRecognitionStatus,
        foods: [RecognizedFoodItem] = [],
        caloriesKcal: Double? = nil,
        message: String? = nil,
        source: DietRecordSource? = nil
    ) -> Bool {
        guard var record = record(id: id) else { return false }
        record.recognitionStatus = status
        record.foods = foods
        record.caloriesKcal = caloriesKcal
        record.recognitionMessage = message
        if let source { record.source = source }
        record.updatedAt = .now
        return upsert(record)
    }

    @discardableResult
    func replaceImages(for id: UUID, with images: [MealImageMetadata]) -> Bool {
        guard var record = record(id: id) else { return false }
        record.images = images
        record.updatedAt = .now
        return upsert(record)
    }

    func remove(id: UUID) {
        meals.removeAll { $0.id == id }
        save()
    }

    func remove(_ record: MealRecord) { remove(id: record.id) }

    func removeAll() {
        meals.removeAll()
        save()
    }

    /// Imports Apple Health dietary-energy samples without collapsing separate
    /// samples into one opaque habit row. The sample identifier is persisted so
    /// a later sync cannot duplicate an already imported meal.
    @discardableResult
    func importEnergySamples(_ samples: [DietEnergySample]) -> Int {
        var imported: [MealRecord] = []
        for sample in samples {
            guard sample.kilocalories.isFinite, sample.kilocalories >= 0,
                  !meals.contains(where: { $0.externalIdentifier == sample.id }),
                  !imported.contains(where: { $0.externalIdentifier == sample.id }),
                  meals.count + imported.count < Self.maxMeals else { continue }

            let date = sample.date
            let record = MealRecord(
                date: date,
                mealType: Self.mealType(for: date, calendar: calendar),
                title: "Apple 健康饮食",
                caloriesKcal: sample.kilocalories,
                note: "Apple 健康 · 饮食能量",
                source: .healthKit,
                externalIdentifier: sample.id,
                createdAt: date,
                updatedAt: date
            )
            guard let cleaned = validated(record), canStoreAdditionalImages(cleaned.images) else { continue }
            imported.append(cleaned)
        }

        guard !imported.isEmpty else { return 0 }
        meals.append(contentsOf: imported)
        sortAndSave()
        return imported.count
    }

    #if DEBUG
    /// Creates a deterministic fixture for SwiftUI previews and focused tests.
    /// Preview data is compiled only in Debug and never falls back to the
    /// user's standard defaults domain.
    static func previewStore(calendar: Calendar = .current) -> DietStore {
        let suiteName = "zhebudeshousi.dietStore.preview.\(UUID().uuidString)"
        guard let previewDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated preview defaults")
        }
        let store = DietStore(
            defaults: previewDefaults,
            calendar: calendar,
            migrateLegacy: false
        )
        store.meals = demoMeals(calendar: calendar)
        store.sortAndSave()
        return store
    }
    #endif

    // MARK: - Validation and derived projections

    private func makeSummary(for day: Date, records: [MealRecord]) -> DietDaySummary {
        let ordered = records.sorted { lhs, rhs in
            if lhs.mealType.sortOrder != rhs.mealType.sortOrder {
                return lhs.mealType.sortOrder < rhs.mealType.sortOrder
            }
            return lhs.date < rhs.date
        }
        let total = ordered
            .compactMap(\.calculatedCaloriesKcal)
            .filter { $0.isFinite && $0 >= 0 }
            .reduce(0, +)
        return DietDaySummary(
            date: day,
            totalCaloriesKcal: (total * 10).rounded() / 10,
            mealCount: ordered.count,
            imageCount: ordered.reduce(0) { $0 + $1.images.count },
            pendingRecognitionCount: ordered.filter { $0.recognitionStatus.isPending || $0.recognitionStatus == .needsReview }.count,
            records: ordered
        )
    }

    private func validated(_ record: MealRecord) -> MealRecord? {
        let now = Date()
        guard record.date.timeIntervalSinceReferenceDate.isFinite,
              record.date >= Self.earliestDate,
              record.date <= now.addingTimeInterval(24 * 60 * 60) else { return nil }
        guard record.images.count <= Self.maxImagesPerMeal,
              record.images.allSatisfy({ $0.normalized().isWithinStorageLimit }) else { return nil }
        guard record.foods.allSatisfy({ item in
            let valueIsValid = item.caloriesKcal.map { $0.isFinite && (0...10_000).contains($0) } ?? true
            let confidenceIsValid = item.confidence.map { $0.isFinite && (0...1).contains($0) } ?? true
            return valueIsValid && confidenceIsValid
        }) else { return nil }
        if let calories = record.caloriesKcal,
           (!calories.isFinite || !(0...20_000).contains(calories)) {
            return nil
        }
        let hasContent = !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !record.images.isEmpty
            || !record.foods.isEmpty
            || record.calculatedCaloriesKcal != nil
        guard hasContent else { return nil }
        return record.normalized()
    }

    private func canStoreAdditionalImages(_ images: [MealImageMetadata]) -> Bool {
        totalImageBytes + images.reduce(0) { $0 + $1.byteCount } <= Self.maxTotalImageBytes
    }

    private static var earliestDate: Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2000, month: 1, day: 1)
        ) ?? .distantPast
    }

    private func sortAndSave() {
        meals.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            if lhs.mealType.sortOrder != rhs.mealType.sortOrder {
                return lhs.mealType.sortOrder < rhs.mealType.sortOrder
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
        save()
    }

    // MARK: - Persistence and migration

    private struct PersistedSnapshot: Codable {
        var version: Int?
        var meals: [MealRecord]?
        var records: [MealRecord]?

        var resolvedMeals: [MealRecord] { meals ?? records ?? [] }
    }

    private func save() {
        let payload = PersistedSnapshot(version: 1, meals: meals, records: nil)
        guard let data = try? JSONEncoder().encode(payload),
              data.count <= Self.maxPersistedPayloadBytes else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(PersistedSnapshot.self, from: data) {
            meals = payload.resolvedMeals.compactMap { validated($0) }
            sortWithoutSaving()
            return
        }
        // A short-lived prototype wrote a bare array. Accept it once so users
        // do not lose those entries when the envelope version is introduced.
        if let legacyMeals = try? decoder.decode([MealRecord].self, from: data) {
            meals = legacyMeals.compactMap { validated($0) }
            sortAndSave()
        }
    }

    private func sortWithoutSaving() {
        meals.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            if lhs.mealType.sortOrder != rhs.mealType.sortOrder {
                return lhs.mealType.sortOrder < rhs.mealType.sortOrder
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    private struct LegacyActivityLog: Decodable {
        var id: UUID?
        var kind: String?
        var title: String?
        var date: Date?
        var amount: String?
        var note: String?
    }

    private struct LegacyAppStateSnapshot: Decodable {
        var logs: [LegacyActivityLog]?
    }

    private func migrateLegacyActivityLogsIfNeeded() {
        guard !defaults.bool(forKey: Self.legacyMigrationKey) else { return }
        guard let data = defaults.data(forKey: Self.legacyAppStateKey) else {
            // Leave the marker unset: an older snapshot may be written later
            // during an upgrade, and should still get one migration attempt.
            return
        }

        let decoder = JSONDecoder()
        guard let snapshot = try? decoder.decode(LegacyAppStateSnapshot.self, from: data) else {
            defaults.set(true, forKey: Self.legacyMigrationKey)
            return
        }

        var didInsert = false
        for log in snapshot.logs ?? [] {
            guard log.kind == "meal", let date = log.date else { continue }
            let title = (log.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let calories = parseCalories(log.amount)
            guard !title.isEmpty || calories != nil else { continue }

            let id = log.id ?? UUID()
            let duplicate = meals.contains { existing in
                existing.id == id
                    || (calendar.isDate(existing.date, inSameDayAs: date)
                        && existing.title == title
                        && existing.calculatedCaloriesKcal == calories)
            }
            guard !duplicate, meals.count < Self.maxMeals else { continue }

            let migrated = MealRecord(
                id: id,
                date: date,
                mealType: inferredMealType(from: log.note),
                title: title,
                caloriesKcal: calories,
                note: log.note ?? "",
                source: .migrated,
                createdAt: date,
                updatedAt: date
            )
            guard let cleaned = validated(migrated), canStoreAdditionalImages(cleaned.images) else { continue }
            meals.append(cleaned)
            didInsert = true
        }

        defaults.set(true, forKey: Self.legacyMigrationKey)
        if didInsert { sortAndSave() }
    }

    private func parseCalories(_ amount: String?) -> Double? {
        guard let amount else { return nil }
        var token = ""
        var started = false
        var decimalSeen = false
        for character in amount {
            if character.isNumber {
                token.append(character)
                started = true
            } else if (character == "." || character == ",") && started && !decimalSeen {
                token.append(".")
                decimalSeen = true
            } else if started {
                break
            }
        }
        guard let value = Double(token), value.isFinite, (0...20_000).contains(value) else { return nil }
        return (value * 10).rounded() / 10
    }

    private func inferredMealType(from note: String?) -> DietMealType {
        let text = note ?? ""
        if text.contains("早餐") { return .breakfast }
        if text.contains("午餐") { return .lunch }
        if text.contains("晚餐") { return .dinner }
        return .snack
    }

    private static func mealType(for date: Date, calendar: Calendar) -> DietMealType {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }

    #if DEBUG
    private static func demoMeals(calendar: Calendar) -> [MealRecord] {
        let today = calendar.startOfDay(for: .now)
        return [
            MealRecord(
                date: calendar.date(byAdding: .minute, value: 30, to: today) ?? today,
                mealType: .breakfast,
                title: "酸奶莓果碗",
                caloriesKcal: 320,
                note: "轻盈的早晨",
                source: .manual
            ),
            MealRecord(
                date: calendar.date(byAdding: .hour, value: 12, to: today) ?? today,
                mealType: .lunch,
                title: "鸡胸肉沙拉",
                caloriesKcal: 420,
                note: "午间补给",
                source: .manual
            )
        ]
    }
    #endif
}
