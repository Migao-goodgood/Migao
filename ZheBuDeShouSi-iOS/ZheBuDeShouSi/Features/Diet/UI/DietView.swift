import SwiftUI
import PhotosUI

/// Food-journal presentation boundary.
///
/// The view owns only selection, picker and review state. `DietStore` remains
/// the single mutation/persistence boundary, while an optional analyzer can
/// be supplied by the app composition root for a local Vision or backend AI
/// implementation.
struct DietView: View {
    @ObservedObject var store: DietStore

    private let analyzer: DietPhotoAnalysisHandler?
    private let calendar: Calendar

    @State private var displayMode = DietDisplayMode.calendar
    @State private var month: Date
    @State private var selectedDate: Date
    @State private var detailDate: Date?
    @State private var isPhotoPickerPresented = false
    @State private var pickerDate: Date
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var uploadedImageData: [Data] = []
    @State private var uploadState = DietUploadState.idle
    @State private var reviewDraft = DietPhotoAnalysisDraft()
    @State private var reviewDate: Date = .now
    @State private var uploadRequestID = UUID()

    init(
        store: DietStore,
        analyzer: DietPhotoAnalysisHandler? = nil,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.analyzer = analyzer
        var localCalendar = calendar
        localCalendar.locale = calendar.locale ?? Locale(identifier: "zh_CN")
        self.calendar = localCalendar
        let today = localCalendar.startOfDay(for: .now)
        _month = State(initialValue: today)
        _selectedDate = State(initialValue: today)
        _pickerDate = State(initialValue: today)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

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
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 118)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(DietPalette.paper.ignoresSafeArea())

            if let detailDate {
                DietCenteredOverlay(onDismiss: dismissDetail) {
                    DietDayDetailModal(
                        date: detailDate,
                        meals: store.meals(on: detailDate),
                        summary: store.summary(for: detailDate),
                        onDismiss: dismissDetail,
                        onUpload: { beginUpload(for: detailDate) },
                        onRemove: { store.remove($0) }
                    )
                }
            }

            if uploadState.isBusy {
                DietCenteredOverlay(onDismiss: cancelReview) {
                    DietRecognitionReviewCard(
                        draft: $reviewDraft,
                        imageData: uploadedImageData,
                        isLoading: true,
                        errorMessage: nil,
                        onConfirm: {},
                        onCancel: cancelReview
                    )
                }
            } else if case .review = uploadState {
                DietCenteredOverlay(onDismiss: cancelReview) {
                    DietRecognitionReviewCard(
                        draft: $reviewDraft,
                        imageData: uploadedImageData,
                        isLoading: uploadState.isBusy,
                        errorMessage: nil,
                        onConfirm: confirmReview,
                        onCancel: cancelReview
                    )
                }
            } else if case .failed(let message) = uploadState {
                DietCenteredOverlay(onDismiss: cancelReview) {
                    DietRecognitionReviewCard(
                        draft: $reviewDraft,
                        imageData: uploadedImageData,
                        isLoading: false,
                        errorMessage: message,
                        onConfirm: confirmReview,
                        onCancel: cancelReview
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
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            DietPageHeader(
                month: month,
                totalCalories: Int(monthSummaries.reduce(0) { $0 + $1.totalCaloriesKcal }.rounded()),
                recordedDays: monthSummaries.filter(\.hasMeals).count,
                onPreviousMonth: { shiftMonth(by: -1) },
                onNextMonth: { shiftMonth(by: 1) },
                onToday: jumpToToday
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { beginUpload(for: selectedDate) } label: {
                ZStack {
                    Circle()
                        .fill(DietPalette.pink)
                        .frame(width: 46, height: 46)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: DietPalette.pink.opacity(0.25), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上传饮食照片")
            .padding(.top, 2)
        }
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

    private func beginUpload(for date: Date) {
        pickerDate = calendar.startOfDay(for: date)
        selectedPhotoItems = []
        uploadRequestID = UUID()
        // Keep the upload/review surface as the only active overlay. The day
        // detail is restored after a successful confirmation.
        detailDate = nil
        isPhotoPickerPresented = true
    }

    private func loadPhotos(_ items: [PhotosPickerItem], for date: Date) {
        let requestID = uploadRequestID
        uploadState = .loading
        reviewDate = date

        Task { @MainActor in
            var data: [Data] = []
            for item in items.prefix(6) {
                if let image = try? await item.loadTransferable(type: Data.self),
                   !image.isEmpty {
                    data.append(image)
                }
            }

            guard requestID == uploadRequestID else { return }
            guard !data.isEmpty else {
                uploadedImageData = []
                uploadState = .failed("没有读取到照片，请重新选择。")
                return
            }

            uploadedImageData = data
            let request = DietPhotoAnalysisRequest(date: date, imageData: data)
            let analyzedDraft: DietPhotoAnalysisDraft?
            if let analyzer {
                analyzedDraft = await analyzer(request)
            } else {
                analyzedDraft = await DietPhotoAnalysisService.analyze(request: request)
            }
            guard requestID == uploadRequestID else { return }
            reviewDraft = analyzedDraft ?? DietPhotoAnalysisDraft(
                mealType: .snack,
                title: "",
                caloriesKcal: nil,
                foods: [],
                confidence: nil,
                sourceLabel: "照片已载入 · 请手动确认名称和热量"
            )
            uploadState = .review(reviewDraft)
        }
    }

    private func confirmReview() {
        let title = reviewDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let calories = reviewDraft.caloriesKcal.map { max(0, $0) }
        guard !title.isEmpty || calories != nil else { return }

        let images = uploadedImageData.enumerated().map { index, data in
            MealImageMetadata(
                data: data,
                filename: "饮食-\(index + 1).jpg",
                capturedAt: .now
            )
        }
        let source: DietRecordSource = analyzer == nil ? .photo : .ai
        // A meal only reaches the store after the user confirms the review
        // card, so it is no longer pending even when the default on-device
        // analyzer was used.
        let status: DietRecognitionStatus = .recognized
        let saved = store.addMeal(
            date: reviewDate,
            mealType: reviewDraft.mealType,
            title: title,
            caloriesKcal: calories.map(Double.init),
            images: images,
            note: "",
            source: source,
            recognitionStatus: status,
            foods: reviewDraft.foods
        )
        guard saved != nil else {
            uploadState = .failed("这组照片暂时无法保存，请减少照片数量后重试。")
            return
        }
        selectedDate = reviewDate
        detailDate = reviewDate
        cancelReviewStateOnly()
    }

    private func cancelReview() {
        cancelReviewStateOnly()
    }

    private func cancelReviewStateOnly() {
        uploadRequestID = UUID()
        uploadState = .idle
        uploadedImageData = []
        selectedPhotoItems = []
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
