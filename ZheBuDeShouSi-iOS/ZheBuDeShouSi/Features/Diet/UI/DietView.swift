import SwiftUI
import PhotosUI

/// Food-journal presentation boundary.
///
/// The view owns only selection, picker and review state. `DietStore` remains
/// the single mutation/persistence boundary. Photo text recognition runs only
/// through the coordinator's on-device Vision implementation.
struct DietView: View {
    @ObservedObject var store: DietStore

    private let calendar: Calendar
    @StateObject private var capture: DietCaptureCoordinator
    @Environment(\.scenePhase) private var scenePhase

    @State private var displayMode = DietDisplayMode.calendar
    @State private var month: Date
    @State private var selectedDate: Date
    @State private var detailDate: Date?
    @State private var isPhotoPickerPresented = false
    @State private var pickerDate: Date
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var editingMeal: MealRecord?
    @State private var editReturnDate: Date?
    @State private var mealPendingDeletion: MealRecord?
    @State private var draftPendingDeletion: DietCaptureDraft?
    @State private var isDiscardingCapture = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var photoLoadTask: Task<Void, Never>?

    init(
        store: DietStore,
        calendar: Calendar = .current
    ) {
        self.store = store
        var localCalendar = calendar
        localCalendar.locale = calendar.locale ?? Locale(identifier: "zh_CN")
        self.calendar = localCalendar
        _capture = StateObject(wrappedValue: DietCaptureCoordinator(
            store: store, calendar: localCalendar
        ))
        let today = localCalendar.startOfDay(for: .now)
        _month = State(initialValue: today)
        _selectedDate = State(initialValue: today)
        _pickerDate = State(initialValue: today)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: JournalPageLayout.sectionSpacing) {
                    header

                    if let feedbackMessage {
                        HStack(spacing: 8) {
                            Image(systemName: feedbackIsError ? "exclamationmark.circle" : "checkmark.circle.fill")
                            Text(feedbackMessage)
                            Spacer(minLength: 4)
                            Button { self.feedbackMessage = nil } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("关闭提示")
                        }
                        .roundedFont(12, weight: .medium)
                        .foregroundStyle(feedbackIsError ? DietPalette.pinkDeep : DietPalette.muted)
                    }

                    if !store.drafts.isEmpty {
                        DietDraftShelf(
                            drafts: store.drafts,
                            onResume: resumeDraft,
                            onRemove: { draftPendingDeletion = $0 }
                        )
                    }

                    DietMonthToolbar(
                        month: month,
                        onPreviousMonth: { shiftMonth(by: -1) },
                        onNextMonth: { shiftMonth(by: 1) },
                        onToday: jumpToToday
                    )

                    DietDisplayModePicker(selection: $displayMode)

                    if displayMode == .calendar {
                        DietMonthCalendar(
                            month: month,
                            summaries: monthSummaries,
                            selectedDate: $selectedDate,
                            onSelectDate: presentDay
                        )
                    } else {
                        DietMosaicGrid(summaries: monthSummaries, onSelectDate: presentDay)
                    }

                    monthCaption
                }
                .padding(.horizontal, JournalPageLayout.horizontalPadding)
                .padding(.top, JournalPageLayout.topPadding)
                .padding(.bottom, 118)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(JournalPageLayout.pageBackground.ignoresSafeArea())

            if let detailDate {
                DietCenteredOverlay(onDismiss: dismissDetail) {
                    DietDayDetailModal(
                        date: detailDate,
                        meals: store.meals(on: detailDate),
                        summary: store.summary(for: detailDate),
                        onDismiss: dismissDetail,
                        onUpload: { beginUpload(for: detailDate) },
                        onEdit: beginEditing,
                        onRemove: { mealPendingDeletion = $0 }
                    )
                }
            }

            if let editingMeal {
                DietCenteredOverlay(onDismiss: cancelEditing) {
                    DietMealEditModal(
                        meal: editingMeal,
                        onSave: saveEditing,
                        onDismiss: cancelEditing
                    )
                }
            }

            if capture.isPresented {
                // Close/Later run the form's validation. A backdrop tap must
                // not bypass invalid input or accidentally suspend the form.
                DietCenteredOverlay(onDismiss: {}) {
                    DietRecognitionReviewCard(
                        draft: Binding(get: { capture.analysis }, set: { capture.updateAnalysis($0) }),
                        recordedAt: Binding(get: { capture.recordedAt }, set: { capture.updateDate($0) }),
                        imageData: capture.imageData,
                        isLoading: capture.isBusy,
                        errorMessage: capture.errorMessage,
                        onConfirm: confirmReview,
                        onCancel: suspendCapture,
                        onDiscard: { isDiscardingCapture = true },
                        onRetry: { capture.requestAnalysis() }
                    )
                }
            }
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: 6,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            loadPhotos(items, for: pickerDate)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { capture.pauseForDeparture() }
        }
        .onDisappear {
            photoLoadTask?.cancel()
            capture.pauseForDeparture()
        }
        .alert(item: $mealPendingDeletion) { meal in
            Alert(
                title: Text("删除这条饮食记录？"),
                message: Text("照片和热量记录将从本机删除，此操作无法撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    if !store.remove(meal) {
                        showFeedback(store.lastErrorMessage ?? "删除失败，请重试。", isError: true)
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .confirmationDialog("删除这份草稿？", isPresented: Binding(
            get: { draftPendingDeletion != nil },
            set: { if !$0 { draftPendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("删除草稿", role: .destructive) {
                if let pending = draftPendingDeletion, !store.removeDraft(id: pending.id) {
                    showFeedback(store.lastErrorMessage ?? "草稿删除失败，请重试。", isError: true)
                }
                draftPendingDeletion = nil
            }
            Button("取消", role: .cancel) { draftPendingDeletion = nil }
        } message: {
            Text("草稿中的照片和填写内容会被移除，正式饮食记录不受影响。")
        }
        .confirmationDialog("放弃这次记录？", isPresented: $isDiscardingCapture, titleVisibility: .visible) {
            Button("放弃并删除草稿", role: .destructive) {
                if capture.discard() { selectedPhotoItems = [] }
            }
            Button("继续填写", role: .cancel) { }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        DietPageHeader(
            totalCalories: Int(monthSummaries.reduce(0) { $0 + $1.totalCaloriesKcal }.rounded()),
            recordedDays: monthSummaries.filter(\.hasMeals).count,
            knownCaloriesMealCount: monthSummaries.reduce(0) { $0 + $1.knownCaloriesMealCount },
            missingCaloriesMealCount: monthSummaries.reduce(0) { $0 + $1.missingCaloriesMealCount },
            hasEstimatedCalories: monthSummaries.contains(where: \.hasEstimatedCalories),
            onAdd: { beginUpload(for: .now) }
        )
    }

    private var monthCaption: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(DietPalette.pink)
                .frame(width: 6, height: 6)
            Text("点击日期，查看或补充当天的餐桌")
                .roundedFont(10, weight: .medium)
                .foregroundStyle(DietPalette.muted)
            Spacer(minLength: 4)
            if monthSummaries.contains(where: \DietDaySummary.hasPendingRecognition) {
                Label("有待确认记录", systemImage: "sparkles")
                    .roundedFont(10, weight: .bold)
                    .foregroundStyle(DietPalette.lilac)
            }
        }
        .padding(.horizontal, 3)
    }

    private var monthSummaries: [DietDaySummary] {
        store.summaries(inMonth: month)
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        let nextMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: next)
        ) ?? next
        withAnimation(.easeInOut(duration: 0.22)) {
            month = nextMonth
            selectedDate = nextMonth
        }
    }

    private func jumpToToday() {
        let today = calendar.startOfDay(for: .now)
        withAnimation(.easeInOut(duration: 0.22)) {
            month = today
            selectedDate = today
        }
    }

    private func presentDay(_ date: Date) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            selectedDate = calendar.startOfDay(for: date)
            detailDate = calendar.startOfDay(for: date)
        }
    }

    private func dismissDetail() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { detailDate = nil }
    }

    private func beginEditing(_ meal: MealRecord) {
        editReturnDate = detailDate ?? calendar.startOfDay(for: meal.date)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            detailDate = nil
            editingMeal = meal
        }
    }

    private func saveEditing(_ draft: DietMealEditDraft) -> Bool {
        let saved = store.updateMeal(
            id: draft.mealID,
            date: draft.recordedAt,
            mealType: draft.mealType,
            title: draft.trimmedTitle,
            caloriesKcal: draft.caloriesKcal
        )
        guard saved else { return false }
        finishEditing(returningTo: calendar.startOfDay(for: draft.recordedAt))
        showSavedFeedback(for: draft.recordedAt)
        return true
    }

    private func cancelEditing() {
        finishEditing(returningTo: editReturnDate)
    }

    private func finishEditing(returningTo date: Date?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            editingMeal = nil
            if let date {
                selectedDate = date
                month = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
                detailDate = date
            }
            editReturnDate = nil
        }
    }

    private func beginUpload(for date: Date) {
        guard !capture.isPresented || capture.suspend() else { return }
        pickerDate = date
        selectedPhotoItems = []
        // Keep the upload/review surface as the only active overlay. The day
        // detail is restored after a successful confirmation.
        detailDate = nil
        isPhotoPickerPresented = true
    }

    private func loadPhotos(_ items: [PhotosPickerItem], for date: Date) {
        photoLoadTask?.cancel()
        let requestID = capture.beginLoading(for: date)
        photoLoadTask = Task { @MainActor in
            var data: [Data] = []
            for item in items.prefix(6) {
                guard !Task.isCancelled, capture.isCurrent(requestID) else { return }
                do {
                    guard let image = try await item.loadTransferable(type: Data.self), !image.isEmpty else {
                        throw DietPhotoPreparation.Failure.unreadable
                    }
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        try DietPhotoPreparation.prepare(image)
                    }.value
                    data.append(prepared)
                } catch {
                    guard !Task.isCancelled else { return }
                    capture.receivePhotos([], token: requestID, failureMessage: error.localizedDescription)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            capture.receivePhotos(data, token: requestID)
        }
    }

    private func confirmReview() {
        guard let saved = capture.confirm() else { return }
        selectedPhotoItems = []
        selectedDate = calendar.startOfDay(for: saved.date)
        month = calendar.date(from: calendar.dateComponents([.year, .month], from: saved.date)) ?? saved.date
        detailDate = selectedDate
        showSavedFeedback(for: saved.date)
    }

    private func suspendCapture() {
        let hadPhotos = !capture.imageData.isEmpty
        guard capture.suspend() else { return }
        photoLoadTask?.cancel()
        selectedPhotoItems = []
        if hadPhotos { showFeedback("草稿已保存，可在饮食页继续填写。") }
    }

    private func resumeDraft(_ draft: DietCaptureDraft) {
        detailDate = nil
        editingMeal = nil
        selectedPhotoItems = []
        capture.resume(draft)
    }

    private func showSavedFeedback(for date: Date) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        showFeedback("已保存到 \(formatter.string(from: date))")
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        feedbackMessage = message
        feedbackIsError = isError
    }
}

#if DEBUG
struct DietView_Previews: PreviewProvider {
    static var previews: some View {
        DietView(store: DietStore.previewStore())
            .frame(width: 390, height: 844)
    }
}
#endif
