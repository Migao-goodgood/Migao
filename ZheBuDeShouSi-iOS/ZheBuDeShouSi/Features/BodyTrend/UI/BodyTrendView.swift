import SwiftUI
import PhotosUI

#if canImport(SceneKit)
import SceneKit
#endif

private enum BodyEditorial {
    static let paper = Color(hex: "F5F1E8")
    static let ink = Color(hex: "263746")
    static let muted = Color(hex: "78888B")
    static let blue = Color(hex: "A9C8CF")
    static let blueWash = Color(hex: "E4EFF0")
    static let sage = Color(hex: "AFC3B1")
    static let blush = Color(hex: "D9AEB0")
    static let blushWash = Color(hex: "F1DFDA")
    static let rule = Color(hex: "D9D4C9")
}

struct BodyTrendView: View {
    @ObservedObject var state: AppState
    @ObservedObject var store: BodyTrendStore

    @State private var selectedIndex = 0.0
    @State private var reportPhotoItem: PhotosPickerItem?
    @State private var avatarPhotoItem: PhotosPickerItem?
    @State private var reportPhotoData: Data?
    @State private var entryDraft = InBodyEntryDraft()
    @State private var isEntryPresented = false
    @State private var isRecognizing = false
    @State private var isCameraPresented = false
    @State private var statusMessage = ""

    private var orderedSnapshots: [InBodySnapshot] { store.orderedSnapshots }

    private var selectedSnapshot: InBodySnapshot? {
        guard !orderedSnapshots.isEmpty else { return nil }
        let index = min(max(Int(selectedIndex.rounded()), 0), orderedSnapshots.count - 1)
        return orderedSnapshots[index]
    }

    private var selectedPosition: Int {
        guard !orderedSnapshots.isEmpty else { return 0 }
        return min(max(Int(selectedIndex.rounded()), 0), orderedSnapshots.count - 1)
    }

    private var previousSnapshot: InBodySnapshot? {
        guard selectedPosition > 0 else { return nil }
        return orderedSnapshots[selectedPosition - 1]
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let snapshot = selectedSnapshot {
                        avatarStage(snapshot, sceneHeight: populatedSceneHeight(for: proxy.size.height))
                        timeline
                        metrics(snapshot)
                        assessment(snapshot)
                    } else {
                        emptyState(availableHeight: emptyContentHeight(for: proxy.size.height))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 123)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, minHeight: max(0, proxy.size.height - 96), alignment: .top)
            }
        }
        .background(BodyEditorial.paper.ignoresSafeArea())
        .onChange(of: orderedSnapshots.count) { _, count in
            selectedIndex = min(selectedIndex, Double(max(0, count - 1)))
        }
        .onChange(of: reportPhotoItem) { _, item in
            recognizeReport(item)
        }
        .onChange(of: avatarPhotoItem) { _, item in
            loadAvatarImage(item)
        }
        #if os(iOS) && canImport(VisionKit)
        .sheet(isPresented: $isCameraPresented) {
            InBodyDocumentScanner(
                onScan: { data in
                    isCameraPresented = false
                    recognizeReportData(data)
                },
                onCancel: { isCameraPresented = false }
            )
            .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: $isEntryPresented) {
            InBodyEntrySheet(
                store: store,
                initialDraft: entryDraft,
                sourcePhotoData: reportPhotoData,
                onSaved: { selectedIndex = Double(max(0, store.orderedSnapshots.count - 1)) }
            )
            .presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Menu {
                    PhotosPicker(selection: $reportPhotoItem, matching: .images) {
                        Label("从相册上传", systemImage: "photo")
                    }
                    #if os(iOS) && canImport(VisionKit)
                    Button {
                        isCameraPresented = true
                    } label: {
                        Label("拍照扫描", systemImage: "camera")
                    }
                    #endif
                    Button(action: openManualEntry) {
                        Label("手动录入", systemImage: "pencil")
                    }
                } label: {
                    headerAction(icon: isRecognizing ? "hourglass" : "doc.viewfinder", title: "扫描", accent: BodyEditorial.blue)
                }
                .buttonStyle(.plain)
                .disabled(isRecognizing)
                .accessibilityLabel("上传或扫描 InBody 报告")

                Button(action: openManualEntry) {
                    headerAction(icon: "plus", title: "录入", accent: BodyEditorial.blush)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("手动录入 InBody 数据")
            }
        }
        .padding(.top, 4)
    }

    private func headerAction(icon: String, title: String, accent: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .roundedFont(10, weight: .bold)
        }
        .foregroundStyle(BodyEditorial.ink)
        .padding(.horizontal, 9)
        .frame(height: 33)
        .background(accent.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle().fill(accent).frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func avatarStage(_ snapshot: InBodySnapshot, sceneHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.date, format: .dateTime.year().month().day())
                        .roundedFont(14, weight: .bold)
                        .foregroundStyle(BodyEditorial.ink)
                    Text(snapshot.source.title)
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(BodyEditorial.muted)
                }
                Spacer()
                MoodBadge(mood: snapshot.mood)
            }

            BodyAvatarSceneView(
                snapshot: snapshot,
                previousSnapshot: previousSnapshot,
                style: store.selectedAvatarStyle,
                imageData: store.avatarImageData
            )
            .frame(height: sceneHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 18)

            HStack(spacing: 0) {
                ForEach(AvatarStyle.allCases) { style in
                    avatarStyleButton(style)
                }

                PhotosPicker(selection: $avatarPhotoItem, matching: .images) {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("上传")
                            .roundedFont(9, weight: .bold)
                    }
                    .foregroundStyle(BodyEditorial.sage)
                    .frame(width: 42, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上传自定义形象")
            }
            .padding(.top, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(BodyEditorial.rule).frame(height: 1)
            }

            Rectangle()
                .fill(BodyEditorial.rule)
                .frame(height: 1)
                .padding(.top, 14)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .overlay(alignment: .leading) {
            Rectangle().fill(BodyEditorial.blush).frame(width: 3)
        }
    }

    private func avatarStyleButton(_ style: AvatarStyle) -> some View {
        let isSelected = store.selectedAvatarStyle == style
        return Button {
            store.setAvatarStyle(style)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: style.symbolName)
                    .font(.system(size: 11, weight: .bold))
                Text(style.title)
                    .roundedFont(9, weight: .bold)
            }
            .foregroundStyle(isSelected ? BodyEditorial.ink : BodyEditorial.muted)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(isSelected ? BodyEditorial.blueWash.opacity(0.65) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? BodyEditorial.ink : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择\(style.title)形象")
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("时间线")
                    .roundedFont(19, weight: .heavy)
                    .foregroundStyle(BodyEditorial.ink)
                Spacer()
                Text(orderedSnapshots.isEmpty ? "暂无记录" : "第 \(selectedPosition + 1) / \(orderedSnapshots.count) 次")
                    .roundedFont(11, weight: .bold)
                    .foregroundStyle(BodyEditorial.muted)
            }

            Slider(
                value: $selectedIndex,
                in: 0...Double(max(0, orderedSnapshots.count - 1)),
                step: 1
            )
            .tint(BodyEditorial.sage)
            .disabled(orderedSnapshots.count < 2)
            .padding(.top, 11)

            HStack {
                if let first = orderedSnapshots.first {
                    Text(dateLabel(first.date))
                }
                Spacer()
                if let last = orderedSnapshots.last {
                    Text(dateLabel(last.date))
                }
            }
            .roundedFont(10, weight: .medium)
            .foregroundStyle(BodyEditorial.muted)
            .padding(.top, 3)

            if orderedSnapshots.count > 1 {
                HStack(spacing: 8) {
                    Text("情绪轨迹")
                        .roundedFont(10, weight: .bold)
                        .foregroundStyle(BodyEditorial.ink)
                    ForEach(Array(orderedSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                        Button {
                            selectedIndex = Double(index)
                        } label: {
                            Circle()
                                .fill(moodColor(snapshot.mood))
                                .frame(width: index == selectedPosition ? 14 : 10, height: index == selectedPosition ? 14 : 10)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .overlay(Circle().stroke(BodyEditorial.ink.opacity(index == selectedPosition ? 0.7 : 0), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 4)
                    Text(selectedSnapshot?.mood?.title ?? "未记录")
                        .roundedFont(10, weight: .medium)
                        .foregroundStyle(BodyEditorial.muted)
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 3)
    }

    private func metrics(_ snapshot: InBodySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .lastTextBaseline) {
                Text("本次数据")
                    .roundedFont(19, weight: .heavy)
                    .foregroundStyle(BodyEditorial.ink)
                Spacer()
                Text("已填写 \(Int(snapshot.completeness * 6)) / 6 项")
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(BodyEditorial.muted)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                BodyMetricCard(title: "体重", value: format(snapshot.weightKg, suffix: " kg"), tint: BodyEditorial.blush)
                BodyMetricCard(title: "体脂率", value: format(snapshot.bodyFatPercentage, suffix: " %"), tint: BodyEditorial.blue)
                BodyMetricCard(title: "骨骼肌", value: format(snapshot.skeletalMuscleKg, suffix: " kg"), tint: BodyEditorial.sage)
                BodyMetricCard(title: "BMI", value: format(snapshot.bmi), tint: BodyEditorial.muted)
                BodyMetricCard(title: "内脏脂肪", value: format(snapshot.visceralFatLevel), tint: BodyEditorial.blush)
                BodyMetricCard(title: "评分", value: format(snapshot.score, decimals: 0), tint: BodyEditorial.blue)
            }
        }
    }

    private func assessment(_ snapshot: InBodySnapshot) -> some View {
        let result = store.assessment(for: snapshot)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: result.status == .attention ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(result.status == .attention ? BodyEditorial.blush : BodyEditorial.sage)
                    .frame(width: 34, height: 34)
                    .background(BodyEditorial.blueWash, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("阶段评价")
                        .roundedFont(11, weight: .bold)
                        .foregroundStyle(BodyEditorial.muted)
                    Text(result.headline)
                        .roundedFont(19, weight: .heavy)
                        .foregroundStyle(BodyEditorial.ink)
                }
                Spacer()
                Text(result.status.title)
                    .roundedFont(10, weight: .bold)
                    .foregroundStyle(BodyEditorial.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 25)
                    .background(BodyEditorial.blueWash, in: Capsule())
            }

            Text(result.summary)
                .roundedFont(12, weight: .medium)
                .foregroundStyle(BodyEditorial.ink)
                .lineSpacing(4)
                .padding(.top, 15)

            if !result.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.highlights, id: \.self) { item in
                        Label(item, systemImage: "checkmark")
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(BodyEditorial.ink)
                    }
                }
                .padding(.top, 12)
            }

            if !result.recommendations.isEmpty {
                Text(result.recommendations.joined(separator: "\n"))
                    .roundedFont(11, weight: .medium)
                    .foregroundStyle(BodyEditorial.muted)
                    .lineSpacing(4)
                    .padding(.top, 12)
            }

            Text(result.disclaimer)
                .roundedFont(9, weight: .medium)
                .foregroundStyle(BodyEditorial.muted)
                .padding(.top, 14)
        }
        .padding(17)
        .background(BodyEditorial.blushWash.opacity(0.42), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(BodyEditorial.blush).frame(width: 3)
        }
    }

    private func emptyState(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            BodyAvatarSceneView(snapshot: nil, previousSnapshot: nil, style: store.selectedAvatarStyle, imageData: store.avatarImageData)
                .frame(height: emptySceneHeight(for: availableHeight))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("还没有 InBody 记录")
                .roundedFont(21, weight: .heavy)
                .foregroundStyle(BodyEditorial.ink)
                .padding(.top, 18)
            Text("使用右上角扫描或录入，开始记录第一份数据")
                .roundedFont(12, weight: .medium)
                .foregroundStyle(BodyEditorial.muted)
                .padding(.top, 7)
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(BodyEditorial.sage)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
            Rectangle()
                .fill(BodyEditorial.rule)
                .frame(height: 1)
                .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity, minHeight: availableHeight, alignment: .center)
        .padding(.top, 8)
    }

    private func populatedSceneHeight(for viewportHeight: CGFloat) -> CGFloat {
        min(390, max(300, viewportHeight * 0.38))
    }

    private func emptyContentHeight(for viewportHeight: CGFloat) -> CGFloat {
        max(620, viewportHeight - 96)
    }

    private func emptySceneHeight(for contentHeight: CGFloat) -> CGFloat {
        min(560, max(420, contentHeight * 0.62))
    }

    private func openManualEntry() {
        reportPhotoData = nil
        var draft = InBodyEntryDraft()
        draft.weight = String(format: "%.1f", state.weight)
        entryDraft = draft
        isEntryPresented = true
    }

    private func recognizeReport(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    statusMessage = "照片读取失败，请重试或手动录入"
                    reportPhotoItem = nil
                }
                return
            }
            await MainActor.run { reportPhotoItem = nil }
            recognizeReportData(data)
        }
    }

    private func recognizeReportData(_ data: Data) {
        isRecognizing = true
        statusMessage = "正在识别报告，请核对识别结果"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                InBodyOCRService.recognize(data: data)
            }.value
            await MainActor.run {
                reportPhotoData = data
                entryDraft = InBodyEntryDraft(ocr: result)
                isRecognizing = false
                statusMessage = result.matchedFieldCount > 0 ? "已识别 \(result.matchedFieldCount) 项，请确认后保存" : "未识别到关键数字，请手动补全"
                isEntryPresented = true
            }
        }
    }

    private func loadAvatarImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                if store.setAvatarImageData(data) {
                    store.setAvatarStyle(.custom)
                } else {
                    statusMessage = "形象图片过大，请选择较小的图片"
                }
                avatarPhotoItem = nil
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func moodColor(_ mood: MoodLevel?) -> Color {
        switch mood {
        case .excellent, .good: return BodyEditorial.sage
        case .neutral: return BodyEditorial.blue
        case .low, .veryLow: return BodyEditorial.blush
        case nil: return BodyEditorial.rule
        }
    }

    private func format(_ value: Double?, suffix: String = "", decimals: Int = 1) -> String {
        guard let value else { return "--" }
        return String(format: "%.*f%@", decimals, value, suffix)
    }
}

private struct InBodyEntryDraft {
    var date = Date()
    var weight = ""
    var bodyFat = ""
    var muscle = ""
    var visceral = ""
    var bmi = ""
    var score = ""
    var mood: MoodLevel?
    var note = ""

    init() {}

    init(ocr: InBodyOCRResult) {
        weight = ocr.weightKg.map { String(format: "%.1f", $0) } ?? ""
        bodyFat = ocr.bodyFatPercent.map { String(format: "%.1f", $0) } ?? ""
        muscle = ocr.skeletalMuscleKg.map { String(format: "%.1f", $0) } ?? ""
        visceral = ocr.visceralFatLevel.map { String(format: "%.1f", $0) } ?? ""
        bmi = ocr.bmi.map { String(format: "%.1f", $0) } ?? ""
        score = ocr.score.map(String.init) ?? ""
    }
}

private struct InBodyEntrySheet: View {
    @ObservedObject var store: BodyTrendStore
    let initialDraft: InBodyEntryDraft
    let sourcePhotoData: Data?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var weight: String
    @State private var bodyFat: String
    @State private var muscle: String
    @State private var visceral: String
    @State private var bmi: String
    @State private var score: String
    @State private var mood: MoodLevel?
    @State private var note: String
    @State private var error = ""

    init(store: BodyTrendStore, initialDraft: InBodyEntryDraft, sourcePhotoData: Data?, onSaved: @escaping () -> Void) {
        self.store = store
        self.initialDraft = initialDraft
        self.sourcePhotoData = sourcePhotoData
        self.onSaved = onSaved
        _date = State(initialValue: initialDraft.date)
        _weight = State(initialValue: initialDraft.weight)
        _bodyFat = State(initialValue: initialDraft.bodyFat)
        _muscle = State(initialValue: initialDraft.muscle)
        _visceral = State(initialValue: initialDraft.visceral)
        _bmi = State(initialValue: initialDraft.bmi)
        _score = State(initialValue: initialDraft.score)
        _mood = State(initialValue: initialDraft.mood)
        _note = State(initialValue: initialDraft.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("测量日期", selection: $date, displayedComponents: .date)
                    field("体重（kg）", text: $weight, required: true)
                } header: {
                    Text("基本数据")
                }

                Section {
                    field("体脂率（%）", text: $bodyFat)
                    field("骨骼肌（kg）", text: $muscle)
                    field("内脏脂肪等级", text: $visceral)
                    field("BMI", text: $bmi)
                    field("InBody 评分", text: $score)
                } header: {
                    Text("身体成分")
                }

                Section {
                    Picker("测量时的心情", selection: $mood) {
                        Text("未记录").tag(MoodLevel?.none)
                        ForEach(MoodLevel.allCases) { item in
                            Text("\(item.emoji)  \(item.title)").tag(Optional(item))
                        }
                    }
                    TextField("备注（选填）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("当时状态")
                }

                if !error.isEmpty {
                    Text(error)
                        .foregroundStyle(BodyEditorial.blush)
                        .font(.footnote)
                }

                Text("照片识别结果仅作为草稿，请核对纸面数据后保存。评价只用于健康记录参考。")
                    .font(.footnote)
                    .foregroundStyle(BodyEditorial.muted)
            }
            .navigationTitle("录入 InBody")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, required: Bool = false) -> some View {
        LabeledContent(title) {
            TextField(required ? "必填" : "选填", text: text)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }

    private func save() {
        guard let weightValue = Double(weight.replacingOccurrences(of: ",", with: ".")), (20...400).contains(weightValue) else {
            error = "请输入 20 至 400 kg 之间的体重"
            return
        }

        let source: InBodyDataSource = sourcePhotoData == nil ? .manual : .ocr
        let record = InBodySnapshot(
            date: date,
            weightKg: weightValue,
            bodyFatPercentage: value(bodyFat),
            skeletalMuscleKg: value(muscle),
            bmi: value(bmi),
            visceralFatLevel: value(visceral),
            score: value(score),
            mood: mood,
            note: note,
            source: source,
            parserVersion: source == .ocr ? "vision-1" : nil
        )

        guard store.add(record) else {
            error = "数据未能保存，请检查体重数值"
            return
        }
        onSaved()
        dismiss()
    }

    private func value(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

private struct MoodBadge: View {
    let mood: MoodLevel?

    var body: some View {
        HStack(spacing: 5) {
            Text(mood?.emoji ?? "—")
                .font(.system(size: 13))
            Text(mood?.title ?? "未记录心情")
                .roundedFont(10, weight: .bold)
        }
        .foregroundStyle(BodyEditorial.ink)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(BodyEditorial.blushWash, in: Capsule())
    }
}

private struct BodyMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .roundedFont(10, weight: .medium)
                .foregroundStyle(BodyEditorial.muted)
            Text(value)
                .roundedFont(20, weight: .heavy)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(.horizontal, 3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BodyEditorial.rule).frame(height: 1)
        }
    }
}

private struct BodyAvatarSceneView: View {
    let snapshot: InBodySnapshot?
    let previousSnapshot: InBodySnapshot?
    let style: AvatarStyle
    let imageData: Data?
    #if canImport(SceneKit)
    @StateObject private var sceneController: BodyAvatarSceneController
    #endif

    init(
        snapshot: InBodySnapshot?,
        previousSnapshot: InBodySnapshot?,
        style: AvatarStyle,
        imageData: Data?
    ) {
        self.snapshot = snapshot
        self.previousSnapshot = previousSnapshot
        self.style = style
        self.imageData = imageData
        #if canImport(SceneKit)
        _sceneController = StateObject(
            wrappedValue: BodyAvatarSceneController(
                input: BodyAvatarSceneInput(
                    snapshot: snapshot,
                    previousSnapshot: previousSnapshot,
                    style: style,
                    imageData: imageData
                )
            )
        )
        #endif
    }

    var body: some View {
        #if canImport(SceneKit)
        SceneView(
            scene: sceneController.scene,
            options: [.allowsCameraControl]
        )
        .onChange(of: sceneInput) { _, input in
            sceneController.update(input: input)
        }
        #else
        ZStack {
            BodyEditorial.blueWash
            Image(systemName: style.symbolName)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(BodyEditorial.sage)
        }
        #endif
    }

    #if canImport(SceneKit)
    private var sceneInput: BodyAvatarSceneInput {
        BodyAvatarSceneInput(
            snapshot: snapshot,
            previousSnapshot: previousSnapshot,
            style: style,
            imageData: imageData
        )
    }
    #endif
}
