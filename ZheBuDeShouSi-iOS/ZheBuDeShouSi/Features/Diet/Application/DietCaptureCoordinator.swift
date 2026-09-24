import Foundation
import Combine

/// Owns an in-progress capture independently of the photo picker and views.
/// Photos are persisted as a recoverable draft before optional recognition.
/// Session tokens prevent late picker/recognizer results from reviving a
/// dismissed draft or overwriting a different meal.
@MainActor
final class DietCaptureCoordinator: ObservableObject {
    enum Phase { case idle, loadingPhotos, analyzing, review }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var draft: DietCaptureDraft?
    @Published private(set) var errorMessage: String?

    private let store: DietStore
    private let analyzer: DietPhotoAnalysisHandler?
    private let calendar: Calendar
    private var requestID = UUID()
    private var analysisTask: Task<Void, Never>?
    private var loadingDate: Date = .now

    /// Production always uses on-device Vision. Injection is test-only.
    init(store: DietStore, calendar: Calendar = .current) {
        self.store = store
        self.analyzer = nil
        self.calendar = calendar
    }

    #if DEBUG
    init(store: DietStore, analyzer: DietPhotoAnalysisHandler?, calendar: Calendar = .current) {
        self.store = store
        self.analyzer = analyzer
        self.calendar = calendar
    }
    #endif

    var isPresented: Bool { phase != .idle }
    var isBusy: Bool { phase == .loadingPhotos || phase == .analyzing }
    var imageData: [Data] { draft?.images.compactMap(\.imageData) ?? [] }
    var analysis: DietPhotoAnalysisDraft { draft?.analysis ?? DietPhotoAnalysisDraft() }
    var recordedAt: Date { draft?.date ?? loadingDate }

    @discardableResult
    func beginLoading(for date: Date) -> UUID {
        // Entry points also guard this in the UI, but the application boundary
        // must never clear the only copy of a draft after a write failure.
        if draft != nil, !persist() { return UUID() }
        reset()
        loadingDate = date
        phase = .loadingPhotos
        return requestID
    }

    func isCurrent(_ token: UUID) -> Bool { token == requestID && phase != .idle }

    func receivePhotos(_ photos: [Data], token: UUID, failureMessage: String? = nil) {
        guard isCurrent(token), phase == .loadingPhotos else { return }
        guard !photos.isEmpty else {
            phase = .review
            errorMessage = failureMessage ?? "没有读取到照片，请重新选择。"
            return
        }
        // A batch is all-or-nothing: silently losing one selected image would
        // make a successful save misleading.
        guard failureMessage == nil else {
            phase = .review
            errorMessage = failureMessage
            return
        }
        let now = Date()
        draft = DietCaptureDraft(
            date: loadingDate,
            analysis: DietPhotoAnalysisDraft(
                mealType: suggestedMealType(at: now),
                sourceLabel: "照片可先保存，设备端会读取照片中已有的 kcal 文字"
            ),
            images: photos.enumerated().map { index, data in
                MealImageMetadata(data: data, filename: "饮食-\(index + 1).jpg", capturedAt: now)
            },
            source: .photo,
            createdAt: now,
            updatedAt: now
        )
        phase = .review
        guard persist() else { return }
        requestAnalysis()
    }

    func resume(_ saved: DietCaptureDraft) {
        if draft != nil, !persist() { return }
        reset()
        draft = store.draft(id: saved.id) ?? saved
        phase = .review
    }

    func updateAnalysis(_ value: DietPhotoAnalysisDraft) {
        guard var current = draft, phase == .review else { return }
        current.analysis = value
        current.updatedAt = .now
        draft = current
        _ = persist()
    }

    func updateDate(_ date: Date) {
        guard var current = draft, phase == .review else { return }
        current.date = date
        current.updatedAt = .now
        draft = current
        _ = persist()
    }

    func requestAnalysis() {
        guard draft != nil, persist() else { return }
        invalidateAnalysis()
        startAnalysis(token: requestID)
    }

    /// Closing the review saves rather than discards it. On failure, retain
    /// the overlay and its input so the user can retry.
    @discardableResult
    func suspend() -> Bool {
        if draft != nil, !persist() { return false }
        reset()
        return true
    }

    /// Used when leaving the tab/backgrounding. The draft remains observable
    /// if saving fails; a late analyzer cannot mutate a hidden capture.
    func pauseForDeparture() {
        invalidateAnalysis()
        if draft != nil {
            phase = .review
            _ = persist()
        } else {
            phase = .idle
        }
    }

    @discardableResult
    func confirm() -> MealRecord? {
        guard let id = draft?.id, persist() else { return nil }
        guard let meal = store.confirmDraft(id: id) else {
            phase = .review
            errorMessage = store.lastErrorMessage ?? "这餐暂时无法保存，照片仍保留在草稿中。"
            return nil
        }
        reset()
        return meal
    }

    @discardableResult
    func discard() -> Bool {
        if let id = draft?.id, store.draft(id: id) != nil,
           !store.removeDraft(id: id) {
            errorMessage = store.lastErrorMessage ?? "草稿暂时无法删除，请重试。"
            return false
        }
        reset()
        return true
    }

    private func persist() -> Bool {
        guard let draft else { return true }
        guard store.saveDraft(draft) else {
            errorMessage = store.lastErrorMessage ?? "草稿暂时无法保存，请保留此页面并重试。"
            return false
        }
        errorMessage = nil
        return true
    }

    private func startAnalysis(token: UUID) {
        guard let draft else { return }
        let input = DietPhotoAnalysisRequest(date: draft.date, imageData: imageData)
        phase = .analyzing
        analysisTask = Task { [weak self, analyzer] in
            let result: DietPhotoAnalysisDraft?
            if let analyzer {
                result = await analyzer(input)
            } else {
                result = await Task.detached(priority: .userInitiated) {
                    await DietPhotoAnalysisService.analyze(request: input)
                }.value
            }
            guard !Task.isCancelled, let self,
                  self.isCurrent(token), self.phase == .analyzing,
                  var current = self.draft else { return }
            if var result {
                // The selected day can be midnight for historical entries;
                // retain the capture's initial slot until the user edits it.
                result.mealType = current.analysis.mealType
                if !current.analysis.title.isEmpty { result.title = current.analysis.title }
                current.analysis = result
            }
            current.updatedAt = .now
            self.draft = current
            self.phase = .review
            _ = self.persist()
        }
    }

    private func suggestedMealType(at date: Date) -> DietMealType {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }

    private func invalidateAnalysis() {
        requestID = UUID()
        analysisTask?.cancel()
        analysisTask = nil
    }

    private func reset() {
        invalidateAnalysis()
        draft = nil
        errorMessage = nil
        phase = .idle
    }
}
