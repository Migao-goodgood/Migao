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
    @Published private(set) var drafts: [DietCaptureDraft] = []
    @Published private(set) var lastErrorMessage: String?

    private var deletedExternalIdentifiers: Set<String> = []
    private let defaults: UserDefaults
    private let calendar: Calendar
    /// Writers must either replace the entire snapshot or throw without
    /// changing it. The injectable boundary makes failure rollback testable.
    private let persistSnapshot: (Data, String) throws -> Void

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        migrateLegacy: Bool = true,
        persistSnapshot: ((Data, String) throws -> Void)? = nil
    ) {
        self.defaults = defaults
        var normalizedCalendar = calendar
        normalizedCalendar.locale = calendar.locale ?? Locale(identifier: "zh_CN")
        self.calendar = normalizedCalendar
        self.persistSnapshot = persistSnapshot ?? { data, key in
            defaults.set(data, forKey: key)
        }
        load()

        if migrateLegacy {
            migrateLegacyActivityLogsIfNeeded()
        }
    }

    var latest: MealRecord? { meals.first }

    var totalImageBytes: Int {
        imageBytes(meals: meals, drafts: drafts)
    }

    var supportedDateRange: ClosedRange<Date> {
        let first = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        return first...tomorrow.addingTimeInterval(-0.001)
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

    func draft(id: UUID) -> DietCaptureDraft? {
        drafts.first { $0.id == id }
    }

    @discardableResult
    func saveDraft(_ draft: DietCaptureDraft) -> Bool {
        guard record(id: draft.id) == nil else {
            return fail("这条饮食已经保存，请在当天记录里编辑。")
        }
        guard let cleaned = validated(draft) else { return false }
        var updated = drafts
        if let index = updated.firstIndex(where: { $0.id == cleaned.id }) {
            updated[index] = cleaned
        } else {
            updated.append(cleaned)
        }
        return commit(meals: meals, drafts: updated, deletedIDs: deletedExternalIdentifiers)
    }

    @discardableResult
    func removeDraft(id: UUID) -> Bool {
        guard draft(id: id) != nil else { return fail("这份草稿已不存在。") }
        return commit(meals: meals, drafts: drafts.filter { $0.id != id }, deletedIDs: deletedExternalIdentifiers)
    }

    /// One snapshot write transfers a draft into confirmed records. Clearing
    /// the total explicitly keeps it unknown, including food-level estimates.
    @discardableResult
    func confirmDraft(id: UUID) -> MealRecord? {
        if let existing = record(id: id) {
            lastErrorMessage = nil
            return existing
        }
        guard let capture = draft(id: id) else {
            fail("这份草稿已不存在，请重新选择照片。")
            return nil
        }
        let calories = capture.analysis.caloriesKcal.map(Double.init)
        let foods = capture.analysis.foods.map { food in
            var result = food
            if calories == nil { result.caloriesKcal = nil }
            return result
        }
        let meal = MealRecord(
            id: capture.id,
            date: capture.date,
            mealType: capture.analysis.mealType,
            title: capture.analysis.title,
            caloriesKcal: calories,
            estimatedCaloriesKcal: capture.analysis.isCalorieEstimate ? capture.analysis.estimatedCaloriesKcal : nil,
            portionMultiplier: capture.analysis.isCalorieEstimate ? capture.analysis.portionMultiplier : nil,
            images: capture.images,
            foods: foods,
            recognitionStatus: calories == nil ? .notStarted : .recognized,
            recognitionMessage: "用户已确认",
            source: capture.source,
            createdAt: capture.createdAt,
            updatedAt: .now
        )
        guard let cleaned = validated(meal),
              commit(meals: meals + [cleaned], drafts: drafts.filter { $0.id != id }, deletedIDs: deletedExternalIdentifiers) else {
            return nil
        }
        return record(id: id)
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
        guard meals.allSatisfy({ $0.id != record.id }), draft(id: record.id) == nil else {
            return fail("这条饮食已存在，请勿重复保存。")
        }
        guard let cleaned = validated(record) else { return false }
        return commit(meals: meals + [cleaned], drafts: drafts, deletedIDs: deletedExternalIdentifiers)
    }

    /// Inserts or replaces a record by ID.
    @discardableResult
    func upsert(_ record: MealRecord) -> Bool {
        guard let cleaned = validated(record) else { return false }
        guard draft(id: cleaned.id) == nil else {
            return fail("这条饮食仍在草稿中，请先确认草稿。")
        }
        var updated = meals
        if let index = updated.firstIndex(where: { $0.id == cleaned.id }) {
            updated[index] = cleaned
        } else {
            updated.append(cleaned)
        }
        return commit(meals: updated, drafts: drafts, deletedIDs: deletedExternalIdentifiers)
    }

    /// Alias for edit screens.
    @discardableResult
    func update(_ record: MealRecord) -> Bool { upsert(record) }

    /// Strict edit path for an existing meal. Identity, photos, source metadata,
    /// creation time, notes, and external IDs remain owned by the stored record.
    @discardableResult
    func updateMeal(
        id: UUID,
        date: Date,
        mealType: DietMealType,
        title: String,
        caloriesKcal: Double?
    ) -> Bool {
        guard var record = record(id: id) else { return fail("这条饮食已不存在。") }
        if caloriesKcal == nil || caloriesKcal != record.caloriesKcal {
            record.estimatedCaloriesKcal = nil
            record.portionMultiplier = nil
        }
        record.date = date
        record.mealType = mealType
        record.title = title
        record.caloriesKcal = caloriesKcal
        if caloriesKcal == nil {
            record.foods = record.foods.map { food in
                var copy = food
                copy.caloriesKcal = nil
                return copy
            }
        }
        record.recognitionStatus = caloriesKcal == nil ? .notStarted : .recognized
        record.recognitionMessage = "用户已确认"
        record.updatedAt = .now
        return upsert(record)
    }

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
        guard var record = record(id: id) else { return fail("这条饮食已不存在。") }
        record.recognitionStatus = status
        record.foods = foods
        record.caloriesKcal = caloriesKcal
        // This legacy recognition API has no AI provenance contract. A new
        // numeric result must not inherit an unrelated earlier estimate.
        record.estimatedCaloriesKcal = nil
        record.portionMultiplier = nil
        record.recognitionMessage = message
        if let source { record.source = source }
        record.updatedAt = .now
        return upsert(record)
    }

    @discardableResult
    func replaceImages(for id: UUID, with images: [MealImageMetadata]) -> Bool {
        guard var record = record(id: id) else { return fail("这条饮食已不存在。") }
        record.images = images
        record.updatedAt = .now
        return upsert(record)
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        guard let record = record(id: id) else { return fail("这条饮食已不存在。") }
        var deletedIDs = deletedExternalIdentifiers
        if let externalIdentifier = record.externalIdentifier,
           !externalIdentifier.isEmpty {
            deletedIDs.insert(externalIdentifier)
        }
        return commit(meals: meals.filter { $0.id != id }, drafts: drafts, deletedIDs: deletedIDs)
    }

    @discardableResult
    func remove(_ record: MealRecord) -> Bool { remove(id: record.id) }

    @discardableResult
    func removeAll() -> Bool {
        let deletedIDs = deletedExternalIdentifiers.union(meals.compactMap(\.externalIdentifier))
        return commit(meals: [], drafts: [], deletedIDs: deletedIDs)
    }

    /// Imports Apple Health dietary-energy samples without collapsing separate
    /// samples into one opaque habit row. The sample identifier is persisted so
    /// a later sync cannot duplicate an already imported meal.
    @discardableResult
    func importEnergySamples(_ samples: [DietEnergySample]) -> Int {
        var imported: [MealRecord] = []
        for sample in samples {
            guard sample.kilocalories.isFinite, sample.kilocalories >= 0,
                  !deletedExternalIdentifiers.contains(sample.id),
                  !meals.contains(where: { $0.externalIdentifier == sample.id }),
                  !imported.contains(where: { $0.externalIdentifier == sample.id }) else { continue }

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
            guard let cleaned = validated(record) else { continue }
            imported.append(cleaned)
        }

        guard !imported.isEmpty else { return 0 }
        return commit(meals: meals + imported, drafts: drafts, deletedIDs: deletedExternalIdentifiers) ? imported.count : 0
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
        _ = store.commit(meals: demoMeals(calendar: calendar), drafts: [], deletedIDs: [])
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
        guard validateDate(record.date), validateImages(record.images), validateFoods(record.foods) else { return nil }
        if let calories = record.caloriesKcal,
           (!calories.isFinite || !(0...20_000).contains(calories)) {
            fail("热量请填写 0 至 20000 kcal，或留空稍后补充。")
            return nil
        }
        let cleaned = record.normalized()
        let hasContent = !cleaned.title.isEmpty || !cleaned.images.isEmpty
            || !cleaned.foods.isEmpty || cleaned.calculatedCaloriesKcal != nil
        guard hasContent else {
            fail("请添加照片、名称或热量后再保存。")
            return nil
        }
        return cleaned
    }

    private func validated(_ draft: DietCaptureDraft) -> DietCaptureDraft? {
        guard validateDate(draft.date), validateImages(draft.images), validateFoods(draft.analysis.foods) else { return nil }
        guard draft.createdAt.timeIntervalSinceReferenceDate.isFinite,
              draft.updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            fail("草稿时间无效，请重新选择照片。")
            return nil
        }
        if let value = draft.analysis.caloriesKcal, !(0...20_000).contains(value) {
            fail("热量请填写 0 至 20000 kcal，或留空稍后补充。")
            return nil
        }
        if let confidence = draft.analysis.confidence, !confidence.isFinite || !(0...1).contains(confidence) {
            fail("识别结果无效，请手动核对后再保存。")
            return nil
        }
        if (draft.analysis.estimatedCaloriesKcal != nil || draft.analysis.portionMultiplier != nil)
            && !draft.analysis.isCalorieEstimate {
            fail("估算热量与份量不一致，请重新核对或手动填写热量。")
            return nil
        }
        var cleaned = draft
        cleaned.images = draft.images.map { $0.normalized() }
        cleaned.analysis.title = String(draft.analysis.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        cleaned.analysis.sourceLabel = String(draft.analysis.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        cleaned.analysis.foods = draft.analysis.foods.map { $0.normalized() }.filter { !$0.name.isEmpty }
        guard !cleaned.images.isEmpty || !cleaned.analysis.title.isEmpty
                || cleaned.analysis.caloriesKcal != nil || !cleaned.analysis.foods.isEmpty else {
            fail("请添加照片、名称或热量后再保存草稿。")
            return nil
        }
        return cleaned
    }

    private func validateDate(_ date: Date) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              supportedDateRange.contains(date) else {
            return fail("记录日期须在 2000 年 1 月 1 日至今天之间。")
        }
        return true
    }

    private func validateImages(_ images: [MealImageMetadata]) -> Bool {
        guard images.count <= Self.maxImagesPerMeal else { return fail("每条饮食最多保存 6 张照片，请分次记录。") }
        guard images.allSatisfy({ $0.normalized().isWithinStorageLimit }) else {
            return fail("照片为空或超过 5 MB，请重新选择较小的照片。")
        }
        return true
    }

    private func validateFoods(_ foods: [RecognizedFoodItem]) -> Bool {
        guard foods.count <= 40,
              foods.allSatisfy({ item in
                  let caloriesValid = item.caloriesKcal.map { $0.isFinite && (0...10_000).contains($0) } ?? true
                  let confidenceValid = item.confidence.map { $0.isFinite && (0...1).contains($0) } ?? true
                  return caloriesValid && confidenceValid
              }) else {
            return fail("识别结果超出有效范围，请核对后再保存。")
        }
        return true
    }

    @discardableResult
    private func fail(_ message: String) -> Bool {
        lastErrorMessage = message
        return false
    }

    private func sortedMeals(_ records: [MealRecord]) -> [MealRecord] {
        records.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            if lhs.mealType.sortOrder != rhs.mealType.sortOrder {
                return lhs.mealType.sortOrder < rhs.mealType.sortOrder
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    // MARK: - Persistence and migration

    private struct PersistedSnapshot: Codable {
        var version: Int?
        var meals: [MealRecord]?
        var records: [MealRecord]?
        var drafts: [DietCaptureDraft]?
        var deletedExternalIdentifiers: [String]?

        var resolvedMeals: [MealRecord] { meals ?? records ?? [] }
    }

    /// Stage and encode a complete candidate before publishing any mutation.
    /// Drafts count toward the same limits but never enter meal projections.
    private func commit(meals: [MealRecord], drafts: [DietCaptureDraft], deletedIDs: Set<String>) -> Bool {
        guard meals.count + drafts.count <= Self.maxMeals else {
            return fail("饮食记录与草稿已达 2000 条，请先整理后再保存。")
        }
        let IDs = meals.map(\.id) + drafts.map(\.id)
        guard Set(IDs).count == IDs.count else { return fail("饮食记录重复，请重新打开后再试。") }
        guard imageBytes(meals: meals, drafts: drafts) <= Self.maxTotalImageBytes else {
            return fail("本地饮食照片已达容量上限，请先整理不需要的照片或草稿。")
        }
        let sortedMeals = sortedMeals(meals)
        let sortedDrafts = drafts.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString > $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
        let payload = PersistedSnapshot(
            version: 3,
            meals: sortedMeals,
            records: nil,
            drafts: sortedDrafts,
            deletedExternalIdentifiers: deletedIDs.sorted()
        )
        do {
            let data = try JSONEncoder().encode(payload)
            guard data.count <= Self.maxPersistedPayloadBytes else {
                return fail("本地饮食数据已达容量上限，本次修改尚未保存，请先整理记录。")
            }
            try persistSnapshot(data, Self.storageKey)
            self.meals = sortedMeals
            self.drafts = sortedDrafts
            deletedExternalIdentifiers = deletedIDs
            lastErrorMessage = nil
            return true
        } catch {
            return fail("保存失败，本次修改尚未保存，请保留当前内容并重试。")
        }
    }

    private func imageBytes(meals: [MealRecord], drafts: [DietCaptureDraft]) -> Int {
        meals.reduce(0) { $0 + $1.images.reduce(0) { $0 + $1.byteCount } }
            + drafts.reduce(0) { $0 + $1.images.reduce(0) { $0 + $1.byteCount } }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(PersistedSnapshot.self, from: data) {
            restore(meals: payload.resolvedMeals, drafts: payload.drafts ?? [])
            deletedExternalIdentifiers = Set(payload.deletedExternalIdentifiers ?? [])
            return
        }
        // A short-lived prototype wrote a bare array. Accept it once so users
        // do not lose those entries when the envelope version is introduced.
        if let legacyMeals = try? decoder.decode([MealRecord].self, from: data) {
            restore(meals: legacyMeals, drafts: [])
        } else {
            fail("本地饮食数据暂时无法读取，请保留原数据后重试。")
        }
    }

    /// Read legacy envelopes without rewriting them. Invalid entries cannot
    /// become confirmed data, and a failed load never replaces stored bytes.
    private func restore(meals records: [MealRecord], drafts captures: [DietCaptureDraft]) {
        var seen: Set<UUID> = []
        meals = sortedMeals(records.compactMap { record in
            guard let cleaned = validated(record), seen.insert(cleaned.id).inserted else { return nil }
            return cleaned
        })
        drafts = captures.compactMap { capture in
            guard let cleaned = validated(capture), seen.insert(cleaned.id).inserted else { return nil }
            return cleaned
        }.sorted { $0.updatedAt > $1.updatedAt }
        if meals.count + drafts.count != records.count + captures.count {
            fail("部分饮食记录或草稿无效，未计入统计；原始本地数据尚未改写。")
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

        var migratedMeals = meals
        for log in snapshot.logs ?? [] {
            guard log.kind == "meal", let date = log.date else { continue }
            let title = (log.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let calories = parseCalories(log.amount)
            guard !title.isEmpty || calories != nil else { continue }

            let id = log.id ?? UUID()
            let duplicate = migratedMeals.contains { existing in
                existing.id == id
                    || (calendar.isDate(existing.date, inSameDayAs: date)
                        && existing.title == title
                        && existing.calculatedCaloriesKcal == calories)
            }
            guard !duplicate, draft(id: id) == nil else { continue }

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
            guard let cleaned = validated(migrated) else { continue }
            migratedMeals.append(cleaned)
        }

        if migratedMeals != meals,
           !commit(meals: migratedMeals, drafts: drafts, deletedIDs: deletedExternalIdentifiers) { return }
        defaults.set(true, forKey: Self.legacyMigrationKey)
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
