import Foundation

/// Standalone contract tests; compiled with the two production Diet domain /
/// store files by run-diet-store-tests.sh, without a simulator or app data.
@main
struct DietStoreReliabilityTests {
    struct Snapshot: Encodable {
        var version = 3
        var meals: [MealRecord] = []
        var drafts: [DietCaptureDraft] = []
        var deletedExternalIdentifiers: [String] = []
    }

    enum SimulatedWriteFailure: Error { case unavailable }

    @MainActor
    final class WriteGate {
        var shouldFail = false
        var writes = 0
        let defaults: UserDefaults

        init(_ defaults: UserDefaults) { self.defaults = defaults }

        func write(_ data: Data, _ key: String) throws {
            if shouldFail { throw SimulatedWriteFailure.unavailable }
            writes += 1
            defaults.set(data, forKey: key)
        }
    }

    static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return result
    }

    static var today: Date { calendar.startOfDay(for: .now) }
    static var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today)! }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        precondition(condition(), message, file: file, line: line)
    }

    @MainActor
    static func isolated(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "Migao.DietReliabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    static func photo(bytes: Int = 20, name: String = "lunch.jpg") -> MealImageMetadata {
        MealImageMetadata(imageData: Data(repeating: 7, count: bytes), filename: name, pixelWidth: 1024, pixelHeight: 768, capturedAt: yesterday, altText: "餐食照片")
    }

    @MainActor
    static func makeStore(_ defaults: UserDefaults, gate: WriteGate? = nil, migrate: Bool = false) -> DietStore {
        DietStore(defaults: defaults, calendar: calendar, migrateLegacy: migrate, persistSnapshot: gate.map { gate in
            { data, key in try gate.write(data, key) }
        })
    }

    @MainActor
    static func main() throws {
        try photoOnlyAndRestoration()
        try confirmationAndDateEditing()
        try knownUnknownAndRealZero()
        try failedWritesAreAtomic()
        try validationAndLimits()
        try encodedPayloadLimit()
        try healthKitTombstones()
        try backwardCompatibility()
        print("PASS: DietStore reliability — 8 contract groups")
    }

    @MainActor
    static func photoOnlyAndRestoration() throws {
        try isolated { defaults in
            let store = makeStore(defaults)
            require(store.meals.isEmpty && store.drafts.isEmpty, "Production stores must start empty")
            let analysis = DietPhotoAnalysisDraft(mealType: .lunch, title: "手动核对", caloriesKcal: nil,
                foods: [RecognizedFoodItem(name: "参考标签", caloriesKcal: 120, confidence: 0.7, servingDescription: "一份")],
                confidence: 0.7, sourceLabel: "设备端识别")
            let capture = DietCaptureDraft(date: yesterday, analysis: analysis, images: [photo()], source: .photo, createdAt: yesterday, updatedAt: today)
            require(store.saveDraft(capture), "Draft should save")
            require(store.summary(for: yesterday).mealCount == 0, "Drafts must not enter daily summaries")
            require(store.totalCalories(on: yesterday) == 0, "OCR suggestions in drafts must not enter totals")
            let restored = makeStore(defaults)
            require(restored.draft(id: capture.id) == capture, "Every draft field including photos and analysis must survive relaunch")

            let photoOnly = DietCaptureDraft(date: today, images: [photo()])
            require(restored.saveDraft(photoOnly), "A photo alone must be a valid draft")
            let meal = restored.confirmDraft(id: photoOnly.id)
            require(meal?.images == photoOnly.images, "Photo-only confirmation must preserve media")
            require(meal?.calculatedCaloriesKcal == nil && meal?.title == "", "Unknown values must not be invented")
            require(restored.summary(for: today).missingCaloriesMealCount == 1, "Photo-only meals must be counted as missing kcal")
            let twice = makeStore(defaults)
            require(twice.record(id: photoOnly.id) == meal, "Photo-only meals must survive relaunch")
            require(twice.draft(id: capture.id) == capture, "Confirming one draft must not remove another")
            let bytes = try JSONEncoder().encode(capture)
            let decoded = try JSONDecoder().decode(DietCaptureDraft.self, from: bytes)
            require(decoded == capture, "Draft Codable must round-trip")
        }
    }

    @MainActor
    static func confirmationAndDateEditing() throws {
        isolated { defaults in
            let gate = WriteGate(defaults)
            let store = makeStore(defaults, gate: gate)
            let capture = DietCaptureDraft(date: yesterday,
                analysis: DietPhotoAnalysisDraft(mealType: .dinner, caloriesKcal: 450), images: [photo()], source: .ai, createdAt: yesterday)
            require(store.saveDraft(capture), "Draft save")
            let confirmed = store.confirmDraft(id: capture.id)!
            let writes = gate.writes
            require(store.confirmDraft(id: capture.id) == confirmed, "Repeated confirmation must return the same record")
            require(gate.writes == writes && store.meals.count == 1 && store.drafts.isEmpty, "Repeated confirmation must not write or duplicate")
            require(confirmed.id == capture.id && confirmed.source == capture.source && confirmed.createdAt == capture.createdAt, "Confirmation must preserve identity/source/creation time")
            require(!store.saveDraft(capture), "A confirmed ID must not recreate a draft")
            require(store.updateMeal(id: confirmed.id, date: today, mealType: .lunch, title: "更新", caloriesKcal: 500), "Changing the date must save")
            require(store.summary(for: yesterday).mealCount == 0 && store.totalCalories(on: yesterday) == 0, "Old day's summary must update")
            require(store.summary(for: today).mealCount == 1 && store.totalCalories(on: today) == 500, "New day's summary must update")
            let edited = store.record(id: confirmed.id)!
            require(edited.images == confirmed.images && edited.source == confirmed.source && edited.createdAt == confirmed.createdAt, "Editing must preserve immutable record metadata")
            require(makeStore(defaults).record(id: edited.id) == edited, "Edited date and data must survive relaunch")
            require(store.remove(id: edited.id) && makeStore(defaults).meals.isEmpty, "Confirmed deletion must persist")
        }
    }

    @MainActor
    static func knownUnknownAndRealZero() throws {
        isolated { defaults in
            let store = makeStore(defaults)
            let draft = DietCaptureDraft(date: today,
                analysis: DietPhotoAnalysisDraft(foods: [RecognizedFoodItem(name: "OCR 值", caloriesKcal: 999)]), images: [photo()])
            require(store.saveDraft(draft), "Draft with OCR food totals")
            let meal = store.confirmDraft(id: draft.id)!
            require(meal.calculatedCaloriesKcal == nil && meal.foods.first?.caloriesKcal == nil, "Cleared optional total must not fall back to food estimates")
            require(store.addMeal(date: today, caloriesKcal: 0) != nil, "Actual zero must be allowed")
            require(store.addMeal(date: today, caloriesKcal: 250) != nil, "Known calories save")
            let summary = store.summary(for: today)
            require(summary.mealCount == 3 && summary.knownCaloriesMealCount == 2 && summary.missingCaloriesMealCount == 1, "Known/unknown counts distinguish actual zero")
            require(summary.totalCaloriesKcal == 250, "Unknown contributes no invented calories")
            for status in [DietRecognitionStatus.needsReview, .failed] {
                let pending = MealRecord(date: today, title: "待处理", foods: [RecognizedFoodItem(name: "OCR", caloriesKcal: 320)], recognitionStatus: status)
                require(store.add(pending), "Legacy review-status record saves")
                require(store.updateMeal(id: pending.id, date: today, mealType: .snack, title: "已核对", caloriesKcal: nil), "User can clear OCR calories")
                let updated = store.record(id: pending.id)!
                require(updated.calculatedCaloriesKcal == nil && updated.recognitionStatus == .notStarted, "Review/failed should be resolved without invented kcal")
                require(store.updateMeal(id: pending.id, date: today, mealType: .snack, title: "已核对", caloriesKcal: 0), "User can confirm a real zero")
                require(store.record(id: pending.id)?.recognitionStatus == .recognized, "Explicit reviewed value resolves state")
            }
        }
    }

    @MainActor
    static func failedWritesAreAtomic() throws {
        isolated { defaults in
            let gate = WriteGate(defaults)
            let store = makeStore(defaults, gate: gate)
            let original = store.addMeal(date: today, title: "原记录", caloriesKcal: 500, images: [photo()])!
            let draft = DietCaptureDraft(date: yesterday, images: [photo()])
            require(store.saveDraft(draft), "Initial draft saves")
            let persisted = defaults.data(forKey: DietStore.storageKey)
            gate.shouldFail = true
            require(!store.updateMeal(id: original.id, date: yesterday, mealType: .dinner, title: "不应出现", caloriesKcal: 1), "Edit must report failed write")
            require(!store.remove(id: original.id), "Delete must report failed write")
            require(!store.removeDraft(id: draft.id), "Draft deletion must report failed write")
            require(store.confirmDraft(id: draft.id) == nil, "Confirmation must report failed write")
            var editedDraft = draft
            editedDraft.analysis.title = "未保存编辑"
            require(!store.saveDraft(editedDraft), "Draft editing must report failed write")
            require(store.addMeal(title: "无法新增") == nil, "Insertion must report failed write")
            require(!store.removeAll(), "Clear must report failed write")
            require(store.meals == [original] && store.drafts == [draft], "Failed writes must leave in-memory state unchanged")
            require(defaults.data(forKey: DietStore.storageKey) == persisted, "Failed writes must leave stored snapshot unchanged")
            require(store.lastErrorMessage != nil, "Failed writes must provide user-facing error")
            gate.shouldFail = false
            require(store.confirmDraft(id: draft.id) != nil && store.lastErrorMessage == nil, "Retry should succeed and clear stale error")
        }
    }

    @MainActor
    static func validationAndLimits() throws {
        try isolated { defaults in
            let store = makeStore(defaults)
            let good = store.addMeal(date: today, title: "有效记录")!
            let bytes = defaults.data(forKey: DietStore.storageKey)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            require(store.addMeal(date: tomorrow, title: "未来") == nil, "Tomorrow is not an allowed journal date")
            require(!store.updateMeal(id: good.id, date: Date(timeIntervalSinceReferenceDate: .infinity), mealType: .lunch, title: "失效", caloriesKcal: nil), "Non-finite date must fail")
            require(!store.saveDraft(DietCaptureDraft(date: calendar.date(from: DateComponents(year: 1999, month: 12, day: 31))!, images: [photo()])), "Pre-2000 draft date must fail")
            require(!store.saveDraft(DietCaptureDraft(date: today, images: Array(repeating: photo(), count: 7))), "Photo count must fail, never truncate silently")
            require(!store.saveDraft(DietCaptureDraft(date: today, images: [photo(bytes: MealImageMetadata.maxImageBytes + 1)])), "Oversized photo must fail")
            require(!store.saveDraft(DietCaptureDraft(date: today, images: [photo(bytes: 0)])), "Empty image must fail")
            require(store.addMeal(date: today, caloriesKcal: .nan) == nil, "Invalid calories must fail")
            require(defaults.data(forKey: DietStore.storageKey) == bytes && store.meals == [good], "Validation failure must be non-mutating")

            var snapshot = Snapshot(meals: (0..<(DietStore.maxMeals - 1)).map { MealRecord(date: today, title: "餐食 \($0)") }, drafts: [DietCaptureDraft(date: today, images: [photo()])])
            defaults.set(try JSONEncoder().encode(snapshot), forKey: DietStore.storageKey)
            let full = makeStore(defaults)
            require(full.meals.count + full.drafts.count == DietStore.maxMeals, "Seed count")
            let fullBytes = defaults.data(forKey: DietStore.storageKey)
            require(full.addMeal(date: today, title: "超限") == nil && !full.saveDraft(DietCaptureDraft(date: today, images: [photo()])), "Combined record/draft count must enforce limit")
            require(defaults.data(forKey: DietStore.storageKey) == fullBytes, "Count failure must preserve snapshot")
            require(full.confirmDraft(id: full.drafts[0].id) != nil, "At capacity, draft transfer must not double-count")

            snapshot = Snapshot(meals: [MealRecord(date: today, images: [photo(bytes: 5_000_000), photo(bytes: 5_000_000), photo(bytes: 5_000_000)])], drafts: [DietCaptureDraft(date: today, images: [photo(bytes: 1_000_000)])])
            defaults.set(try JSONEncoder().encode(snapshot), forKey: DietStore.storageKey)
            let imageFull = makeStore(defaults)
            require(imageFull.totalImageBytes == DietStore.maxTotalImageBytes, "Drafts must count toward global photo limit")
            let imageBytes = defaults.data(forKey: DietStore.storageKey)
            require(imageFull.addMeal(date: today, images: [photo()]) == nil, "Aggregate photo limit must reject new photos")
            require(!imageFull.saveDraft(DietCaptureDraft(date: today, images: [photo()])), "Aggregate photo limit must also reject draft photos")
            require(defaults.data(forKey: DietStore.storageKey) == imageBytes, "Image limit failure must preserve persisted snapshot")

            let invalidDraft = DietCaptureDraft(date: tomorrow, images: [photo()])
            defaults.set(try JSONEncoder().encode(Snapshot(meals: [good], drafts: [invalidDraft])), forKey: DietStore.storageKey)
            let filtered = makeStore(defaults)
            require(filtered.drafts.isEmpty && filtered.summary(for: today).mealCount == 1 && filtered.summary(for: tomorrow).mealCount == 0, "Invalid persisted drafts never enter confirmed summaries")
        }
    }

    @MainActor
    static func encodedPayloadLimit() throws {
        try isolated { defaults in
            let images = (0..<3).map { MealRecord(date: today, images: [photo(bytes: 5_000_000, name: "\($0).jpg")]) }
            let notes = (0..<1_000).map { MealRecord(date: today, title: "餐食 \($0)", note: String(repeating: "食", count: 900)) }
            let seed = try JSONEncoder().encode(Snapshot(meals: images + notes))
            require(seed.count < DietStore.maxPersistedPayloadBytes && seed.count > 22_700_000, "Seed must isolate encoded payload limit")
            defaults.set(seed, forKey: DietStore.storageKey)
            let store = makeStore(defaults)
            let additional = DietCaptureDraft(date: today, images: [photo(bytes: 1_000_000)])
            require(!store.saveDraft(additional), "Encoded snapshot limit must reject even when raw image/count limits pass")
            require(store.drafts.isEmpty && store.meals.count == images.count + notes.count, "Encoding size failure cannot publish candidate state")
            require(defaults.data(forKey: DietStore.storageKey) == seed, "Encoding size failure cannot overwrite snapshot")
            require(store.lastErrorMessage?.contains("容量上限") == true, "Payload limit must explain failure")
        }
    }

    @MainActor
    static func healthKitTombstones() throws {
        isolated { defaults in
            let gate = WriteGate(defaults)
            let store = makeStore(defaults, gate: gate)
            let sample = DietEnergySample(id: "health-energy-1", date: yesterday, kilocalories: 450)
            require(store.importEnergySamples([sample, sample]) == 1, "HealthKit import must deduplicate within a batch")
            require(store.importEnergySamples([sample]) == 0, "Repeated HealthKit import must be idempotent")
            let record = store.meals[0]
            gate.shouldFail = true
            require(!store.remove(id: record.id), "Failed deletion must not publish tombstone")
            require(store.record(id: record.id) == record, "Failed HealthKit deletion keeps record")
            gate.shouldFail = false
            require(store.remove(id: record.id), "HealthKit deletion saves")
            let reloaded = makeStore(defaults)
            require(reloaded.importEnergySamples([sample]) == 0 && reloaded.meals.isEmpty, "Deletion tombstones survive relaunch and block reimport")
        }
    }

    @MainActor
    static func backwardCompatibility() throws {
        try isolated { defaults in
            let meal = MealRecord(date: yesterday, title: "历史记录", caloriesKcal: 321, recognitionStatus: .needsReview)
            let encoder = JSONEncoder()
            let mealObject = try JSONSerialization.jsonObject(with: encoder.encode(meal))
            for payload in [
                ["version": 1, "records": [mealObject]],
                ["version": 2, "meals": [mealObject], "deletedExternalIdentifiers": ["already-deleted"]]
            ] as [[String: Any]] {
                defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: DietStore.storageKey)
                let restored = makeStore(defaults)
                require(restored.meals == [meal] && restored.drafts.isEmpty, "v1/v2 meals must survive unchanged")
                if payload["version"] as? Int == 2 {
                    require(restored.importEnergySamples([DietEnergySample(id: "already-deleted", date: yesterday, kilocalories: 50)]) == 0, "v2 tombstones stay effective")
                }
            }
            defaults.set(try encoder.encode([meal]), forKey: DietStore.storageKey)
            require(makeStore(defaults).meals == [meal], "Bare prototype arrays remain decodable")

            defaults.removeObject(forKey: DietStore.storageKey)
            let logID = UUID()
            let legacyLog: [String: Any] = ["logs": [["id": logID.uuidString, "kind": "meal", "title": "旧午餐", "date": yesterday.timeIntervalSinceReferenceDate, "amount": "234 kcal", "note": "午餐"]]]
            defaults.set(try JSONSerialization.data(withJSONObject: legacyLog), forKey: "zhebudeshousi.appState")
            let gate = WriteGate(defaults)
            gate.shouldFail = true
            let failedMigration = makeStore(defaults, gate: gate, migrate: true)
            require(failedMigration.meals.isEmpty && defaults.data(forKey: DietStore.storageKey) == nil, "Failed legacy migration must not partially publish")
            require(!defaults.bool(forKey: "zhebudeshousi.dietStore.legacyMigration.v1"), "Failed legacy migration must remain retryable")
            gate.shouldFail = false
            let migrated = makeStore(defaults, gate: gate, migrate: true)
            require(migrated.meals.count == 1 && migrated.meals[0].id == logID && migrated.totalCalories(on: yesterday) == 234, "Legacy meal logs migrate with identity and calories")
            require(makeStore(defaults, migrate: true).meals.count == 1, "Legacy migration must be idempotent")
        }
    }
}
