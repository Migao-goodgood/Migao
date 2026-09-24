import Foundation
import Combine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Standalone regression harness; deliberately uses isolated UserDefaults.
// Compile with DietModels.swift, DietStore.swift, DietCaptureCoordinator.swift,
// DietPhotoAnalysisService.swift, and DietPhotoPreparation.swift.
// No application, UI, or live OCR is run.
@main
@MainActor
struct DietCaptureFlowTests {
    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("suspend keeps photos and ignores late analysis", suspendDuringAnalysis),
            ("discard cannot be revived by late analysis", discardDuringAnalysis),
            ("new capture rejects the prior session's result", replaceSessionDuringAnalysis),
            ("photos can be confirmed while analysis is pending", confirmPhotosDuringAnalysis),
            ("date, meal slot, title and photos survive recreation", editedDraftSurvivesRecreation),
            ("save failure retains the open capture for retry", initialPersistenceFailure),
            ("save failure blocks replacing the only copy of a draft", failedDraftCannotBeReplaced),
            ("confirmation failure retains persisted draft", confirmationFailure),
            ("departure invalidates analysis without losing photos", pauseDuringAnalysis),
            ("default local OCR needs no consent or API", defaultLocalOCR),
            ("local OCR retry, suspend and late result guards", localOCRRetryAndLateResults),
            ("stale photo picker results and partial batches do not save", stalePhotoLoading),
            ("photo preparation rejects corrupt bytes", corruptPhotoPreparation),
            ("photo preparation normalizes orientation, size and metadata", boundedPhotoPreparation)
        ]
        var failures: [String] = []
        for (name, test) in tests {
            do {
                try await test()
                print("PASS: \(name)")
            } catch {
                failures.append("\(name): \(error)")
                print("FAIL: \(name): \(error)")
            }
        }
        if !failures.isEmpty {
            fatalError("Diet capture regression failures: \(failures.joined(separator: "; "))")
        }
        print("All \(tests.count) diet capture flow tests passed.")
    }

    static func suspendDuringAnalysis() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        try await gate.waitForRequests(1)
        let original = try unwrap(store.drafts.first, "photos must persist before OCR")
        try require(coordinator.suspend(), "suspend must save successfully")
        gate.complete(0, with: .init(title: "late OCR", caloriesKcal: 550))
        await drainTasks()
        try require(!coordinator.isPresented && coordinator.draft == nil, "late OCR reopened suspended capture")
        try require(store.draft(id: original.id) == original, "late OCR changed a suspended draft")
        let restored = fixture.makeStore()
        try require(restored.draft(id: original.id)?.images == original.images, "suspended photos were not persisted")
        try require(restored.meals.isEmpty, "draft entered confirmed meals")
    }

    static func discardDuringAnalysis() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        try await gate.waitForRequests(1)
        try require(coordinator.discard(), "discard failed")
        gate.complete(0, with: .init(title: "discarded OCR", caloriesKcal: 800))
        await drainTasks()
        try require(!coordinator.isPresented && coordinator.draft == nil, "discarded capture reopened")
        try require(store.drafts.isEmpty && fixture.makeStore().drafts.isEmpty, "late OCR revived deleted draft")
    }

    static func replaceSessionDuringAnalysis() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let oldToken = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: oldToken)
        try await gate.waitForRequests(1)
        let oldID = try unwrap(coordinator.draft?.id, "missing first capture")
        let newPhoto = Data([4, 5, 6, 7])
        let newToken = coordinator.beginLoading(for: fixture.date.addingTimeInterval(-86_400))
        coordinator.receivePhotos([newPhoto], token: newToken)
        try await gate.waitForRequests(2)
        let newID = try unwrap(coordinator.draft?.id, "missing second capture")
        try require(newID != oldID && !coordinator.isCurrent(oldToken), "new session did not replace request token")
        gate.complete(0, with: .init(title: "wrong meal", caloriesKcal: 900))
        await drainTasks()
        try require(coordinator.draft?.id == newID && coordinator.imageData == [newPhoto], "old result replaced new photos")
        try require(coordinator.analysis.title.isEmpty, "old OCR populated the new session")
        gate.complete(1, with: .init(title: "right meal", caloriesKcal: 420))
        try await waitUntil("new OCR never finished") { coordinator.phase == .review }
        try require(coordinator.analysis.title == "right meal" && coordinator.analysis.caloriesKcal == 420, "current result was lost")
        try require(store.draft(id: oldID)?.analysis.title.isEmpty == true, "old saved draft was mutated")
        try require(store.drafts.count == 2, "starting another capture destroyed the saved first draft")
    }

    static func confirmPhotosDuringAnalysis() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        try await gate.waitForRequests(1)
        try require(coordinator.phase == .analyzing, "test must confirm before OCR finishes")
        let meal = try unwrap(coordinator.confirm(), "photo-only confirmation failed during OCR")
        try require(meal.title.isEmpty && meal.calculatedCaloriesKcal == nil, "unknown values were invented")
        try require(meal.imageData == [fixture.photo] && meal.date == fixture.date, "photo/date changed on confirm")
        try require(!coordinator.isPresented && store.drafts.isEmpty, "confirmation left overlay/draft behind")
        gate.complete(0, with: .init(title: "late title", caloriesKcal: 1_234))
        await drainTasks()
        let restored = fixture.makeStore()
        try require(restored.meals.count == 1 && restored.meals[0] == meal, "late OCR altered a confirmed meal")
        try require(restored.summary(for: fixture.date).missingCaloriesMealCount == 1, "photo-only meal counted as known zero")
        try require(coordinator.confirm() == nil && restored.meals.count == 1, "repeated confirmation duplicated meal")
    }

    static func editedDraftSurvivesRecreation() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        try await gate.waitForRequests(1)
        gate.complete(0, with: .init(title: "OCR title", caloriesKcal: 600))
        try await waitUntil("OCR did not finish") { coordinator.phase == .review }
        var edited = coordinator.analysis
        edited.title = "我的午餐"
        edited.mealType = .lunch
        edited.caloriesKcal = nil
        let selectedDate = fixture.date.addingTimeInterval(-172_800)
        coordinator.updateAnalysis(edited)
        coordinator.updateDate(selectedDate)
        let savedID = try unwrap(coordinator.draft?.id, "missing edited draft")
        let savedImages = coordinator.draft?.images
        try require(coordinator.suspend(), "edited draft failed to suspend")

        let restoredStore = fixture.makeStore()
        let restoredDraft = try unwrap(restoredStore.draft(id: savedID), "draft lost on store recreation")
        let restoredCoordinator = fixture.makeCoordinator(store: restoredStore, gate: DeferredAnalyzer())
        restoredCoordinator.resume(restoredDraft)
        try require(restoredCoordinator.phase == .review, "restored capture is not reviewable")
        try require(restoredCoordinator.recordedAt == selectedDate, "selected date was lost")
        try require(restoredCoordinator.analysis.title == "我的午餐" && restoredCoordinator.analysis.mealType == .lunch, "edited title/slot lost")
        try require(restoredCoordinator.draft?.images == savedImages, "image identity was lost")
        let meal = try unwrap(restoredCoordinator.confirm(), "restored draft cannot confirm")
        try require(meal.id == savedID && meal.date == selectedDate && meal.mealType == .lunch, "confirmation did not keep identity/date/slot")
        try require(meal.title == "我的午餐" && meal.calculatedCaloriesKcal == nil, "confirmation lost the edited fields")
        try require(fixture.makeStore().drafts.isEmpty, "confirmed draft restored again")
    }

    static func initialPersistenceFailure() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        var shouldFail = true
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore(writer: { data, key in
            if shouldFail { throw TestFailure("simulated unavailable storage") }
            fixture.defaults.set(data, forKey: key)
        })
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        try require(coordinator.phase == .review && coordinator.errorMessage != nil, "save failure was not visible")
        try require(coordinator.imageData == [fixture.photo] && store.drafts.isEmpty, "failure discarded photos or published unsaved state")
        try require(!coordinator.suspend() && coordinator.isPresented, "failed suspend closed the capture")
        try require(coordinator.confirm() == nil && coordinator.isPresented, "failed confirm closed the capture")
        shouldFail = false
        let meal = try unwrap(coordinator.confirm(), "saving did not recover after storage recovery")
        try require(meal.imageData == [fixture.photo], "retry lost original photo")
        try require(gate.requests.isEmpty, "OCR ran before photos were recoverable")
    }

    static func confirmationFailure() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        var writes = 0
        var failingWrite: Int?
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore(writer: { data, key in
            writes += 1
            if writes == failingWrite { throw TestFailure("simulated confirmation write failure") }
            fixture.defaults.set(data, forKey: key)
        })
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        try await gate.waitForRequests(1)
        gate.complete(0, with: nil)
        try await waitUntil("nil OCR result did not finish") { coordinator.phase == .review }
        let id = try unwrap(coordinator.draft?.id, "missing persisted capture")
        failingWrite = writes + 2 // confirm() first persists, then transfers into meals.
        try require(coordinator.confirm() == nil, "injected confirmation failure did not occur")
        try require(coordinator.phase == .review && coordinator.errorMessage != nil, "confirmation failure closed the review")
        try require(store.meals.isEmpty && store.draft(id: id) != nil, "failed transfer removed draft or published meal")
        try require(fixture.makeStore().draft(id: id) != nil, "failed transfer lost durable draft")
        failingWrite = nil
        try require(coordinator.confirm()?.id == id, "retry did not confirm the same draft")
    }

    static func failedDraftCannotBeReplaced() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        var shouldFail = false
        let store = fixture.makeStore(writer: { data, key in
            if shouldFail { throw TestFailure("storage remains unavailable") }
            fixture.defaults.set(data, forKey: key)
        })
        let otherDraft = DietCaptureDraft(
            date: fixture.date.addingTimeInterval(-86_400),
            analysis: .init(title: "已有的另一份草稿"),
            images: [MealImageMetadata(data: Data([7, 8, 9]))]
        )
        try require(store.saveDraft(otherDraft), "could not seed another recoverable draft")
        shouldFail = true
        let coordinator = fixture.makeCoordinator(store: store, gate: DeferredAnalyzer())
        let initialToken = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: initialToken)
        let retainedDraft = try unwrap(coordinator.draft, "failed capture lost its draft")
        try require(coordinator.errorMessage != nil && store.draft(id: retainedDraft.id) == nil, "test must retain an unsaved capture")

        let rejectedToken = coordinator.beginLoading(for: fixture.date.addingTimeInterval(-172_800))
        try require(!coordinator.isCurrent(rejectedToken), "blocked beginLoading returned a valid token")
        coordinator.receivePhotos([Data([4, 5, 6])], token: rejectedToken)
        try require(coordinator.draft == retainedDraft && coordinator.phase == .review, "blocked new capture overwrote unsaved photos")

        coordinator.resume(otherDraft)
        try require(coordinator.draft == retainedDraft && coordinator.imageData == [fixture.photo], "resume replaced the only copy of unsaved photos")
        try require(coordinator.recordedAt == fixture.date && coordinator.errorMessage != nil, "failed resume hid the original date/error")
        try require(store.draft(id: otherDraft.id) == otherDraft, "blocked replacement mutated the other draft")

        shouldFail = false
        try require(coordinator.suspend(), "old draft did not save after storage recovery")
        try require(fixture.makeStore().draft(id: retainedDraft.id)?.images == retainedDraft.images, "recovered original draft was not durable")
        try require(fixture.makeStore().draft(id: otherDraft.id) == otherDraft, "recovery overwrote the other draft")
    }

    static func pauseDuringAnalysis() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        try await gate.waitForRequests(1)
        coordinator.pauseForDeparture()
        try require(!coordinator.isCurrent(token) && coordinator.phase == .review, "departure left active recognition token")
        gate.complete(0, with: .init(title: "late background result", caloriesKcal: 500))
        await drainTasks()
        try require(coordinator.imageData == [fixture.photo] && coordinator.analysis.title.isEmpty, "departure lost images or accepted late result")
        try require(fixture.makeStore().drafts.count == 1, "departure did not keep recoverable draft")
    }

    static func stalePhotoLoading() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        let coordinator = fixture.makeCoordinator(store: store, gate: DeferredAnalyzer())
        let staleToken = coordinator.beginLoading(for: fixture.date)
        try require(coordinator.suspend(), "closing photo loading failed")
        coordinator.receivePhotos([fixture.photo], token: staleToken)
        try require(!coordinator.isPresented && store.drafts.isEmpty, "late PhotosPicker result reopened capture")
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token, failureMessage: "第二张照片读取失败")
        try require(coordinator.phase == .review && coordinator.errorMessage == "第二张照片读取失败", "partial batch failure was hidden")
        try require(store.drafts.isEmpty && store.meals.isEmpty, "partial batch silently saved fewer photos")
    }

    static func defaultLocalOCR() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        let coordinator = DietCaptureCoordinator(store: store, calendar: fixture.calendar)
        let blank = try blankJPEG()
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([blank], token: token)
        try require(coordinator.phase == .analyzing, "default constructor must automatically start local OCR")
        let saved = try unwrap(store.drafts.first, "photos must be durable before local OCR")
        try require(fixture.makeStore().draft(id: saved.id)?.images == saved.images, "recognition started before recoverable save")
        // First-use Vision initialization can exceed the short fake-analyzer
        // timeout; this bounded wait does not add network or authorization.
        for _ in 0..<1_000 {
            if coordinator.phase == .review { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try require(coordinator.phase == .review && !coordinator.isBusy, "blank JPEG did not finish local OCR")
        try require(coordinator.analysis.caloriesKcal == nil && coordinator.analysis.title.isEmpty && coordinator.analysis.foods.isEmpty, "blank photo received invented meal values")
        try require(coordinator.analysis.sourceLabel.contains("未读到明确热量"), "local no-text result must explain unknown kcal")
        let meal = try unwrap(coordinator.confirm(), "local no-text result blocked photo-only saving")
        try require(meal.imageData == [blank] && meal.calculatedCaloriesKcal == nil, "local OCR lost photos or invented calories")
        try require(meal.source == .photo && store.drafts.isEmpty, "local OCR must remain a photo record without duplicate draft")
    }

    static func localOCRRetryAndLateResults() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = fixture.makeCoordinator(store: store, gate: gate)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        try await gate.waitForRequests(1)
        try require(coordinator.phase == .analyzing && gate.requests[0].imageData == [fixture.photo], "local analyzer received the wrong capture")
        let visible = DietPhotoAnalysisService.draft(fromRecognizedLines: ["热量 300 kcal", "能量 300 千卡"], date: fixture.date)
        gate.complete(0, with: visible)
        try await waitUntil("local visible kcal response did not finish") { coordinator.phase == .review }
        try require(coordinator.analysis.caloriesKcal == 300 && coordinator.analysis.title.isEmpty && coordinator.analysis.foods.isEmpty, "visible label was not read conservatively")
        let initial = try unwrap(coordinator.draft, "local result lost its draft")
        try require(fixture.makeStore().draft(id: initial.id)?.analysis.caloriesKcal == 300, "local OCR was not durably saved")

        coordinator.requestAnalysis()
        try await gate.waitForRequests(2)
        try require(coordinator.phase == .analyzing, "local OCR retry did not start")
        coordinator.pauseForDeparture()
        try require(coordinator.phase == .review, "leaving during local OCR should restore review")
        try require(coordinator.suspend(), "local OCR could not suspend")
        let suspended = try unwrap(store.draft(id: initial.id), "suspending removed durable draft")
        gate.complete(1, with: DietPhotoAnalysisService.draft(fromRecognizedLines: ["900 kcal"], date: fixture.date))
        await drainTasks()
        try require(coordinator.draft == nil && !coordinator.isPresented, "late local result reopened suspended capture")
        try require(store.draft(id: initial.id) == suspended, "late local result overwrote suspended draft")

        coordinator.resume(suspended)
        coordinator.requestAnalysis()
        try await gate.waitForRequests(3)
        let confirmed = try unwrap(coordinator.confirm(), "pending local retry prevented confirmation")
        try require(confirmed.caloriesKcal == 300, "confirmation lost the last reviewed local result")
        gate.complete(2, with: DietPhotoAnalysisService.draft(fromRecognizedLines: ["1200 kcal"], date: fixture.date))
        await drainTasks()
        let restored = fixture.makeStore()
        try require(restored.record(id: confirmed.id) == confirmed && restored.drafts.isEmpty, "late local result rewrote confirmed meal or revived its draft")
        try require(!coordinator.isPresented && coordinator.draft == nil, "late local result reopened confirmed capture")
    }

    static func blankJPEG() throws -> Data {
        let context = try unwrap(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), "blank fixture context unavailable")
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let image = try unwrap(context.makeImage(), "blank fixture image unavailable")
        let data = NSMutableData()
        let destination = try unwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil), "blank fixture destination unavailable")
        CGImageDestinationAddImage(destination, image, nil)
        try require(CGImageDestinationFinalize(destination), "blank fixture JPEG failed")
        return data as Data
    }

    static func corruptPhotoPreparation() async throws {
        do {
            _ = try DietPhotoPreparation.prepare(Data([0, 1, 2, 3]))
            throw TestFailure("corrupt bytes were accepted as a photo")
        } catch is DietPhotoPreparation.Failure {
            // Expected: the user receives a recoverable unreadable-photo error.
        }
    }

    static func boundedPhotoPreparation() async throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try unwrap(CGContext(
            data: nil, width: 3_200, height: 1_800, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), "could not create fixture image")
        context.setFillColor(CGColor(red: 0.7, green: 0.3, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3_200, height: 1_800))
        let image = try unwrap(context.makeImage(), "fixture image unavailable")
        let original = NSMutableData()
        let destination = try unwrap(CGImageDestinationCreateWithData(
            original, UTType.jpeg.identifier as CFString, 1, nil
        ), "could not encode fixture")
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 31.2,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 121.5,
                kCGImagePropertyGPSLongitudeRef: "E"
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private fixture metadata"]
        ] as CFDictionary)
        try require(CGImageDestinationFinalize(destination), "fixture JPEG was not finalized")
        let prepared = try DietPhotoPreparation.prepare(original as Data)
        try require(!prepared.isEmpty && prepared.count <= MealImageMetadata.maxImageBytes, "prepared image violates the storage bound")
        let source = try unwrap(CGImageSourceCreateWithData(prepared as CFData, nil), "prepared bytes do not decode")
        let properties = try unwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], "prepared metadata unavailable")
        try require(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier, "prepared photo is not JPEG")
        try require((properties[kCGImagePropertyPixelWidth] as? Int) == 900, "orientation was not applied to width")
        try require((properties[kCGImagePropertyPixelHeight] as? Int) == 1_600, "max dimension/orientation is incorrect")
        try require(properties[kCGImagePropertyGPSDictionary] == nil, "GPS metadata leaked into saved photo")
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        try require(exif?[kCGImagePropertyExifUserComment] == nil, "original EXIF comment leaked into saved photo")
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message) }
    }

    static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(message) }
        return value
    }

    static func waitUntil(_ message: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw TestFailure(message)
    }

    static func drainTasks() async {
        // Completion is controllable by continuations; this only gives the
        // canceled task its next turn to exercise the late-result guards.
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private struct Fixture {
    let suite = "Migao.DietCaptureFlowTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let calendar: Calendar
    let date: Date
    let photo = Data([1, 2, 3])

    init() {
        defaults = UserDefaults(suiteName: suite)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        self.calendar = calendar
        date = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now))!
    }

    func makeStore(writer: ((Data, String) throws -> Void)? = nil) -> DietStore {
        DietStore(defaults: defaults, calendar: calendar, migrateLegacy: false, persistSnapshot: writer)
    }

    func makeCoordinator(store: DietStore, gate: DeferredAnalyzer) -> DietCaptureCoordinator {
        DietCaptureCoordinator(store: store, analyzer: { request in
            await gate.analyze(request)
        }, calendar: calendar)
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor
private final class DeferredAnalyzer {
    private(set) var requests: [DietPhotoAnalysisRequest] = []
    private var pending: [Int: CheckedContinuation<DietPhotoAnalysisDraft?, Never>] = [:]

    func analyze(_ request: DietPhotoAnalysisRequest) async -> DietPhotoAnalysisDraft? {
        let index = requests.count
        requests.append(request)
        return await withCheckedContinuation { pending[index] = $0 }
    }

    func waitForRequests(_ count: Int) async throws {
        try await DietCaptureFlowTests.waitUntil("analyzer request did not start") { requests.count >= count }
    }

    func complete(_ index: Int, with value: DietPhotoAnalysisDraft?) {
        guard let continuation = pending.removeValue(forKey: index) else {
            preconditionFailure("No analyzer request at index \(index)")
        }
        continuation.resume(returning: value)
    }
}
