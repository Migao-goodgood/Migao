import SwiftUI
import PhotosUI

struct BodyTrendView: View {
    @ObservedObject var store: BodyTrendStore
    /// Injected at the presentation boundary so a backend or test analyzer
    /// can replace the default local/OCR pipeline without changing the view.
    private let reportAnalyzer: AnyInBodyReportAnalyzer
    /// The app composition root can connect this callback to the platform
    /// notification scheduler without coupling this view to UserNotifications.
    private let onMeasurementScheduleChanged: (InBodyMeasurementSchedule, Date?) async -> Bool
    /// Body weight follows the app-wide display preference; report composition
    /// masses keep their source units so the report remains comparable.
    private let weightUnit: WeightUnit

    @State private var reportPhotoItem: PhotosPickerItem?
    @State private var reportPhotoData: Data?
    @State private var reportWasUploaded = false
    @State private var entryDraft = InBodyEntryDraft()
    @State private var isEntryPresented = false
    @State private var isRemoteAnalysisConsentPresented = false
    @State private var isRecognizing = false
    @State private var statusMessage = ""
    @State private var comparisonSelection = ComparisonSelection.previous
    @State private var selectedTrendMetric = InBodyMetric.weight
    @State private var selectedHistorySnapshot: InBodySnapshot?
    @State private var reminderStatusMessage = ""
    @State private var isUpdatingReminder = false

    init(
        store: BodyTrendStore,
        reportAnalyzer: AnyInBodyReportAnalyzer = .live,
        weightUnit: WeightUnit = .kilograms,
        onMeasurementScheduleChanged: @escaping (InBodyMeasurementSchedule, Date?) async -> Bool = { _, _ in true }
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.reportAnalyzer = reportAnalyzer
        self.weightUnit = weightUnit
        self.onMeasurementScheduleChanged = onMeasurementScheduleChanged
    }

    private var orderedSnapshots: [InBodySnapshot] { store.orderedSnapshots }
    private var latestSnapshot: InBodySnapshot? { orderedSnapshots.last }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if isRecognizing || !statusMessage.isEmpty {
                    analysisStatus
                }

                measurementSchedule

                if let latest = latestSnapshot {
                    InBodyLatestSummaryView(
                        latest: latest,
                        recordCount: orderedSnapshots.count,
                        progress: store.comparison(for: latest, weightUnit: weightUnit),
                        selection: $comparisonSelection,
                        weightUnit: weightUnit
                    )
                    InBodyTrendSection(
                        snapshots: orderedSnapshots,
                        selectedMetric: $selectedTrendMetric,
                        weightUnit: weightUnit
                    )
                    InBodyAssessmentView(result: store.comparison(for: latest, weightUnit: weightUnit).analysis)
                    InBodyHistorySection(
                        snapshots: orderedSnapshots,
                        latestSnapshotID: latestSnapshot?.id,
                        comparisonFor: { store.comparison(for: $0, weightUnit: weightUnit).previous },
                        onSelect: { selectedHistorySnapshot = $0 },
                        weightUnit: weightUnit
                    )
                } else {
                    InBodyEmptyState()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 123)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(BodyEditorial.paper.ignoresSafeArea())
        .onChange(of: reportPhotoItem) { _, item in
            recognizeReport(item)
        }
        .sheet(isPresented: $isEntryPresented, onDismiss: {
            reportPhotoData = nil
            reportWasUploaded = false
        }) {
            InBodyEntrySheet(
                store: store,
                initialDraft: entryDraft,
                sourceWasUploaded: reportWasUploaded,
                onSaved: {
                    comparisonSelection = .previous
                    selectedHistorySnapshot = nil
                    statusMessage = "报告已保存，身体变化对比已更新"
                    if store.measurementSchedule.isEnabled {
                        synchronizeMeasurementReminder(store.measurementSchedule)
                    }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(item: $selectedHistorySnapshot) { snapshot in
            InBodyHistoryDetailSheet(
                snapshot: snapshot,
                comparison: store.comparison(for: snapshot, weightUnit: weightUnit).previous,
                onDelete: {
                    store.remove(snapshot)
                    selectedHistorySnapshot = nil
                    if store.measurementSchedule.isEnabled {
                        synchronizeMeasurementReminder(store.measurementSchedule)
                    }
                },
                weightUnit: weightUnit
            )
                .presentationDetents([.medium, .large])
        }
        .alert(
            "发送报告进行 AI 分析？",
            isPresented: $isRemoteAnalysisConsentPresented
        ) {
            Button("同意并使用 AI 分析") {
                guard let data = reportPhotoData else { return }
                recognizeReportData(data, using: reportAnalyzer)
            }
            Button("仅在设备上识别") {
                guard let data = reportPhotoData else { return }
                recognizeReportData(data, using: .local)
            }
            Button("取消", role: .cancel) {
                reportPhotoData = nil
                reportWasUploaded = false
            }
        } message: {
            Text("报告可能包含健康数据和个人信息。选择 AI 分析会把这张图片发送到产品配置的安全服务器；设备端识别不会上传图片。")
        }
        .task {
            if store.measurementSchedule.isEnabled {
                synchronizeMeasurementReminder(store.measurementSchedule)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("身体数据")
                    .roundedFont(26, weight: .heavy)
                    .foregroundStyle(BodyEditorial.ink)
            }

            Spacer(minLength: 8)

            PhotosPicker(selection: $reportPhotoItem, matching: .images) {
                AddMediaActionLabel(
                    systemName: isRecognizing ? "hourglass" : "photo",
                    foregroundColor: isRecognizing ? BodyEditorial.gold : BodyEditorial.blue,
                    surfaceColor: isRecognizing ? BodyEditorial.gold.opacity(0.14) : BodyEditorial.blueWash,
                    badgeColor: BodyEditorial.blue,
                    borderColor: BodyEditorial.paper,
                    showsBadge: !isRecognizing
                )
            }
            .buttonStyle(.plain)
            .disabled(isRecognizing)
            .accessibilityLabel(isRecognizing ? "正在分析 InBody 报告" : "上传 InBody 报告照片")
        }
    }

    private var analysisStatus: some View {
        HStack(spacing: 10) {
            if isRecognizing {
                ProgressView()
                    .controlSize(.small)
                    .tint(BodyEditorial.blue)
            } else {
                Image(systemName: analysisStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(analysisStatusIsError ? BodyEditorial.blush : BodyEditorial.sage)
            }
            Text(statusMessage)
                .roundedFont(11, weight: .medium)
                .foregroundStyle(BodyEditorial.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 40)
        .background(BodyEditorial.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(BodyEditorial.rule, lineWidth: 1)
        }
    }

    private var analysisStatusIsError: Bool {
        statusMessage.contains("失败") || statusMessage.contains("未识别")
    }

    private var measurementSchedule: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BodyEditorial.gold)
                    .frame(width: 36, height: 36)
                    .background(BodyEditorial.gold.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("定期测量")
                        .roundedFont(16, weight: .heavy)
                        .foregroundStyle(BodyEditorial.ink)
                    Text(measurementScheduleText)
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(BodyEditorial.muted)
                }

                Spacer(minLength: 6)

                Toggle("", isOn: measurementEnabledBinding)
                    .labelsHidden()
                    .tint(BodyEditorial.sage)
                    .disabled(isUpdatingReminder)
                    .accessibilityLabel("启用定期测量")
            }

            Picker("测量周期", selection: measurementIntervalBinding) {
                ForEach(availableMeasurementIntervals) { interval in
                    Text("\(interval.weekCount) 周").tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .tint(BodyEditorial.blue)
            .disabled(!store.measurementSchedule.isEnabled || isUpdatingReminder)
            .opacity(store.measurementSchedule.isEnabled ? 1 : 0.48)
            .accessibilityLabel("选择 InBody 测量周期")

            if !reminderStatusMessage.isEmpty {
                Text(reminderStatusMessage)
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(BodyEditorial.muted)
            }
        }
        .padding(15)
        .background(BodyEditorial.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BodyEditorial.rule, lineWidth: 1)
        }
    }

    private var availableMeasurementIntervals: [InBodyMeasurementInterval] {
        InBodyMeasurementInterval.allCases.filter { [2, 4, 6, 8].contains($0.weekCount) }
    }

    private var measurementEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.measurementSchedule.isEnabled },
            set: { isEnabled in
                var schedule = store.measurementSchedule
                schedule.isEnabled = isEnabled
                updateMeasurementSchedule(schedule)
            }
        )
    }

    private var measurementIntervalBinding: Binding<InBodyMeasurementInterval> {
        Binding(
            get: { store.measurementSchedule.interval },
            set: { interval in
                var schedule = store.measurementSchedule
                schedule.interval = interval
                schedule.isEnabled = true
                updateMeasurementSchedule(schedule)
            }
        )
    }

    private var measurementScheduleText: String {
        switch store.measurementDueStatus() {
        case .disabled:
            return "提醒已关闭"
        case .noMeasurements:
            return "每 \(store.measurementSchedule.interval.weekCount) 周整理一份身体数据"
        case .due:
            return "已到下一次测量周期"
        case .upcoming(let dueDate):
            let start = Calendar.current.startOfDay(for: .now)
            let due = Calendar.current.startOfDay(for: dueDate)
            let days = max(0, Calendar.current.dateComponents([.day], from: start, to: due).day ?? 0)
            return "下次建议 \(dateLabel(dueDate))，还有 \(days) 天"
        }
    }

    private func updateMeasurementSchedule(_ schedule: InBodyMeasurementSchedule) {
        let normalized = schedule.normalized()
        store.updateMeasurementSchedule(normalized)
        synchronizeMeasurementReminder(normalized)
    }

    private func synchronizeMeasurementReminder(_ schedule: InBodyMeasurementSchedule) {
        isUpdatingReminder = true
        reminderStatusMessage = ""
        Task { @MainActor in
            let applied = await onMeasurementScheduleChanged(schedule, latestSnapshot?.date)
            isUpdatingReminder = false
            if schedule.isEnabled, !applied {
                var disabledSchedule = schedule
                disabledSchedule.isEnabled = false
                store.updateMeasurementSchedule(disabledSchedule)
                reminderStatusMessage = "通知权限未开启，定期提醒已关闭"
            } else if schedule.isEnabled {
                reminderStatusMessage = latestSnapshot == nil
                    ? "保存第一份报告后开始计算提醒"
                    : "下一次测量提醒已更新"
            }
        }
    }

    private func recognizeReport(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    statusMessage = "照片读取失败，请重试"
                    reportPhotoItem = nil
                }
                return
            }
            await MainActor.run { reportPhotoItem = nil }
            if reportAnalyzer.requiresRemoteUploadConsent {
                reportPhotoData = data
                isRemoteAnalysisConsentPresented = true
            } else {
                recognizeReportData(data, using: reportAnalyzer)
            }
        }
    }

    private func recognizeReportData(
        _ data: Data,
        using analyzer: AnyInBodyReportAnalyzer
    ) {
        isRecognizing = true
        statusMessage = "正在分析报告，请稍候"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                await analyzer.analyze(data: data)
            }.value
            await MainActor.run {
                reportPhotoData = nil
                reportWasUploaded = true
                entryDraft = InBodyEntryDraft(analysis: result)
                isRecognizing = false
                statusMessage = result.message ?? (result.recognizedFieldCount > 0 ? "已识别 \(result.recognizedFieldCount) 项，请确认后保存" : "未识别到关键数字，请核对报告")
                isEntryPresented = true
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
