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
            ("remote analysis waits for consent and declining keeps photos", remoteConsentDeclineAndUnconfigured),
            ("consented AI estimates persist and late results stay invalidated", remoteConsentAllowAndLateResults),
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

    static func remoteConsentDeclineAndUnconfigured() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = DietCaptureCoordinator(store: store, analyzer: { request in
            await gate.analyze(request)
        }, calendar: fixture.calendar, requiresRemoteConsent: true)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        await drainTasks()
        try require(coordinator.phase == .awaitingConsent, "remote handler must wait for consent")
        try require(gate.requests.isEmpty, "photo data reached analyzer before consent")
        let saved = try unwrap(store.drafts.first, "photos must be durable before asking for consent")
        try require(fixture.makeStore().draft(id: saved.id)?.images == saved.images, "consent prompt appeared before recoverable save")
        coordinator.declineRemoteAnalysis()
        coordinator.allowRemoteAnalysis() // A stale consent action after declining is ignored.
        await drainTasks()
        try require(coordinator.phase == .review && gate.requests.isEmpty, "declining/stale allow still called analyzer")
        try require(coordinator.analysis.sourceLabel.contains("未发送"), "decline must clearly state photos were not sent")
        let meal = try unwrap(coordinator.confirm(), "declining remote analysis blocked photo-only saving")
        try require(meal.imageData == [fixture.photo] && meal.calculatedCaloriesKcal == nil, "decline lost photos or invented calories")
        try require(!meal.isCalorieEstimate && store.drafts.isEmpty, "declined meal was labeled an estimate or left a duplicate draft")

        let unconfigured = DietCaptureCoordinator(store: store, calendar: fixture.calendar, requiresRemoteConsent: true)
        let unconfiguredToken = unconfigured.beginLoading(for: fixture.date)
        unconfigured.receivePhotos([Data([4, 5, 6])], token: unconfiguredToken)
        await drainTasks()
        try require(unconfigured.phase == .review && unconfigured.analysis.sourceLabel.contains("尚未开通"), "default nil analyzer must honestly show unavailable status")
        unconfigured.requestAnalysis()
        unconfigured.allowRemoteAnalysis()
        await drainTasks()
        try require(unconfigured.phase == .review && !unconfigured.isBusy, "nil analyzer must not launch recognition or consent")
        try require(unconfigured.analysis.caloriesKcal == nil && !unconfigured.analysis.isCalorieEstimate, "unconfigured flow invented an estimate")
        try require(unconfigured.confirm()?.imageData == [Data([4, 5, 6])], "unconfigured flow must still save photos")
        try require(gate.requests.isEmpty, "no handler call is allowed in declined/unconfigured flows")
    }

    static func remoteConsentAllowAndLateResults() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let gate = DeferredAnalyzer()
        let store = fixture.makeStore()
        let coordinator = DietCaptureCoordinator(store: store, analyzer: { request in
            await gate.analyze(request)
        }, calendar: fixture.calendar, requiresRemoteConsent: true)
        let token = coordinator.beginLoading(for: fixture.date)
        coordinator.receivePhotos([fixture.photo], token: token)
        await drainTasks()
        try require(gate.requests.isEmpty && coordinator.phase == .awaitingConsent, "initial call escaped consent gate")
        coordinator.allowRemoteAnalysis()
        coordinator.allowRemoteAnalysis() // Repeated taps cannot start duplicate requests.
        try await gate.waitForRequests(1)
        await drainTasks()
        try require(gate.requests.count == 1 && coordinator.phase == .analyzing, "explicit allow must start exactly one request")
        try require(gate.requests[0].imageData == [fixture.photo], "consented analyzer received the wrong capture")
        let estimate = DietPhotoAnalysisDraft(caloriesKcal: 300, confidence: 0.8,
            sourceLabel: "AI 估算", estimatedCaloriesKcal: 600, portionMultiplier: 0.5)
        gate.complete(0, with: estimate)
        try await waitUntil("consented AI response did not finish") { coordinator.phase == .review }
        try require(coordinator.analysis.isCalorieEstimate && coordinator.analysis.estimatedCaloriesKcal == 600
            && coordinator.analysis.portionMultiplier == 0.5, "capture discarded valid estimate provenance")
        let initial = try unwrap(coordinator.draft, "AI result lost its draft")
        try require(fixture.makeStore().draft(id: initial.id)?.analysis.isCalorieEstimate == true, "AI provenance was not durably saved")

        coordinator.requestAnalysis()
        await drainTasks()
        try require(coordinator.phase == .awaitingConsent && gate.requests.count == 1, "retry must ask before uploading again")
        coordinator.allowRemoteAnalysis()
        try await gate.waitForRequests(2)
        coordinator.pauseForDeparture()
        try require(coordinator.phase == .review, "leaving during consented analysis should restore review")
        try require(coordinator.suspend(), "consented analysis could not suspend")
        let suspended = try unwrap(store.draft(id: initial.id), "suspending removed durable draft")
        gate.complete(1, with: .init(caloriesKcal: 900, sourceLabel: "late AI", estimatedCaloriesKcal: 900, portionMultiplier: 1))
        await drainTasks()
        try require(coordinator.draft == nil && !coordinator.isPresented, "late consented result reopened suspended capture")
        try require(store.draft(id: initial.id) == suspended, "late consented result overwrote suspended estimate")

        coordinator.resume(suspended)
        coordinator.requestAnalysis()
        await drainTasks()
        try require(coordinator.phase == .awaitingConsent && gate.requests.count == 2, "resuming must not reuse earlier upload consent")
        coordinator.allowRemoteAnalysis()
        try await gate.waitForRequests(3)
        let confirmed = try unwrap(coordinator.confirm(), "pending retry prevented confirmation of the saved estimate")
        try require(confirmed.isCalorieEstimate && confirmed.caloriesKcal == 300, "confirmation lost the last reviewed estimate")
        gate.complete(2, with: .init(caloriesKcal: 1_200, sourceLabel: "late AI", estimatedCaloriesKcal: 1_200, portionMultiplier: 1))
        await drainTasks()
        let restored = fixture.makeStore()
        try require(restored.record(id: confirmed.id) == confirmed && restored.drafts.isEmpty, "late consented result rewrote confirmed meal or revived its draft")
        try require(!coordinator.isPresented && coordinator.draft == nil, "late consented result reopened confirmed capture")
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
