import SwiftUI

struct InBodyEntryDraft {
    var date = Date()
    var height = ""
    var age = ""
    var sex = ""
    var deviceModel = ""
    var weight = ""
    var bodyFat = ""
    var bodyFatMass = ""
    var muscle = ""
    var visceral = ""
    var bmi = ""
    var waistHipRatio = ""
    var score = ""
    var totalBodyWater = ""
    var protein = ""
    var mineral = ""
    var fatFreeMass = ""
    var bodyCellMass = ""
    var basalMetabolicRate = ""
    var smi = ""
    var note = ""
    var source: InBodyDataSource = .manual
    var parserVersion: String?
    var ocrConfidence: Double?
    var analysisMessage: String?

    init() {}

    init(analysis: InBodyReportAnalysis) {
        let now = Date()
        if let measuredAt = analysis.measurementDate,
           measuredAt >= Self.earliestMeasurementDate,
           measuredAt <= now {
            date = measuredAt
        } else {
            date = now
        }
        height = analysis.heightCm.map { String(format: "%.1f", $0) } ?? ""
        age = analysis.age.map(String.init) ?? ""
        sex = normalizedSex(analysis.sex)
        deviceModel = analysis.deviceModel ?? ""
        weight = analysis.weightKg.map { String(format: "%.1f", $0) } ?? ""
        bodyFat = analysis.bodyFatPercent.map { String(format: "%.1f", $0) } ?? ""
        bodyFatMass = analysis.bodyFatKg.map { String(format: "%.1f", $0) } ?? ""
        muscle = analysis.skeletalMuscleKg.map { String(format: "%.1f", $0) } ?? ""
        visceral = analysis.visceralFatLevel.map { String(format: "%.1f", $0) } ?? ""
        bmi = analysis.bmi.map { String(format: "%.1f", $0) } ?? ""
        waistHipRatio = analysis.waistHipRatio.map { String(format: "%.2f", $0) } ?? ""
        score = analysis.score.map(String.init) ?? ""
        totalBodyWater = analysis.totalBodyWaterL.map { String(format: "%.1f", $0) } ?? ""
        protein = analysis.proteinKg.map { String(format: "%.1f", $0) } ?? ""
        mineral = analysis.mineralKg.map { String(format: "%.2f", $0) } ?? ""
        fatFreeMass = analysis.fatFreeMassKg.map { String(format: "%.1f", $0) } ?? ""
        bodyCellMass = analysis.bodyCellMassKg.map { String(format: "%.1f", $0) } ?? ""
        basalMetabolicRate = analysis.basalMetabolicRate.map { String(format: "%.0f", $0) } ?? ""
        smi = analysis.smiKgPerM2.map { String(format: "%.1f", $0) } ?? ""
        source = analysis.dataSource
        parserVersion = analysis.parserVersion
        ocrConfidence = analysis.confidence
        analysisMessage = analysis.message
    }

    fileprivate static var earliestMeasurementDate: Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2000, month: 1, day: 1)
        ) ?? .distantPast
    }

    private func normalizedSex(_ value: String?) -> String {
        guard let value else { return "" }
        if value.localizedCaseInsensitiveContains("女") || value.lowercased().contains("female") { return "女性" }
        if value.localizedCaseInsensitiveContains("男") || value.lowercased().contains("male") { return "男性" }
        return ""
    }

    init(ocr: InBodyOCRResult) {
        self.init(analysis: ocr)
    }
}

struct InBodyEntrySheet: View {
    @ObservedObject var store: BodyTrendStore
    let initialDraft: InBodyEntryDraft
    let sourceWasUploaded: Bool
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var height: String
    @State private var age: String
    @State private var sex: String
    @State private var deviceModel: String
    @State private var weight: String
    @State private var bodyFat: String
    @State private var bodyFatMass: String
    @State private var muscle: String
    @State private var visceral: String
    @State private var bmi: String
    @State private var waistHipRatio: String
    @State private var score: String
    @State private var totalBodyWater: String
    @State private var protein: String
    @State private var mineral: String
    @State private var fatFreeMass: String
    @State private var bodyCellMass: String
    @State private var basalMetabolicRate: String
    @State private var smi: String
    @State private var note: String
    @State private var error = ""
    @State private var isExtendedExpanded = false

    init(store: BodyTrendStore, initialDraft: InBodyEntryDraft, sourceWasUploaded: Bool, onSaved: @escaping () -> Void) {
        self.store = store
        self.initialDraft = initialDraft
        self.sourceWasUploaded = sourceWasUploaded
        self.onSaved = onSaved
        _date = State(initialValue: initialDraft.date)
        _height = State(initialValue: initialDraft.height)
        _age = State(initialValue: initialDraft.age)
        _sex = State(initialValue: initialDraft.sex)
        _deviceModel = State(initialValue: initialDraft.deviceModel)
        _weight = State(initialValue: initialDraft.weight)
        _bodyFat = State(initialValue: initialDraft.bodyFat)
        _bodyFatMass = State(initialValue: initialDraft.bodyFatMass)
        _muscle = State(initialValue: initialDraft.muscle)
        _visceral = State(initialValue: initialDraft.visceral)
        _bmi = State(initialValue: initialDraft.bmi)
        _waistHipRatio = State(initialValue: initialDraft.waistHipRatio)
        _score = State(initialValue: initialDraft.score)
        _totalBodyWater = State(initialValue: initialDraft.totalBodyWater)
        _protein = State(initialValue: initialDraft.protein)
        _mineral = State(initialValue: initialDraft.mineral)
        _fatFreeMass = State(initialValue: initialDraft.fatFreeMass)
        _bodyCellMass = State(initialValue: initialDraft.bodyCellMass)
        _basalMetabolicRate = State(initialValue: initialDraft.basalMetabolicRate)
        _smi = State(initialValue: initialDraft.smi)
        _note = State(initialValue: initialDraft.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "测量时间",
                        selection: $date,
                        in: InBodyEntryDraft.earliestMeasurementDate...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    field("体重（kg）", text: $weight, required: true)
                    field("身高（cm）", text: $height)
                    field("年龄", text: $age)
                    Picker("性别", selection: $sex) {
                        Text("未填写").tag("")
                        Text("女性").tag("女性")
                        Text("男性").tag("男性")
                    }
                    plainField("设备型号", text: $deviceModel)
                } header: {
                    Text("基本数据")
                }

                Section {
                    field("体脂率（%）", text: $bodyFat)
                    field("体脂肪量（kg）", text: $bodyFatMass)
                    field("骨骼肌量（kg）", text: $muscle)
                    field("BMI", text: $bmi)
                    field("腰臀比", text: $waistHipRatio)
                    field("内脏脂肪等级", text: $visceral)
                    field("InBody 评分", text: $score)
                } header: {
                    Text("身体成分")
                }

                Section {
                    DisclosureGroup("扩展指标", isExpanded: $isExtendedExpanded) {
                        field("总体水分（L）", text: $totalBodyWater)
                        field("蛋白质（kg）", text: $protein)
                        field("矿物质（kg）", text: $mineral)
                        field("去脂体重（kg）", text: $fatFreeMass)
                        field("身体细胞量（kg）", text: $bodyCellMass)
                        field("基础代谢（kcal）", text: $basalMetabolicRate)
                        field("SMI（kg/m²）", text: $smi)
                    }
                }

                Section {
                    TextField("备注（选填）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("测量备注")
                }

                if !error.isEmpty {
                    Text(error)
                        .foregroundStyle(BodyEditorial.blush)
                        .font(.footnote)
                }

                if let analysisMessage = initialDraft.analysisMessage,
                   !analysisMessage.isEmpty {
                    Label(analysisMessage, systemImage: initialDraft.source == .ai ? "sparkles" : "iphone")
                        .font(.footnote)
                        .foregroundStyle(BodyEditorial.muted)
                }

                Text("识别结果仅作为草稿，请核对纸面数据后保存。身体变化分析只用于健康记录参考。")
                    .font(.footnote)
                    .foregroundStyle(BodyEditorial.muted)

                Text("App 不会把原始报告照片写入本地历史。")
                    .font(.footnote)
                    .foregroundStyle(BodyEditorial.muted)
            }
            .navigationTitle("核对分析结果")
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

    private func plainField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("选填", text: text)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }

    private func save() {
        error = ""
        guard let weightValue = value(weight), weightValue.isFinite, (20...400).contains(weightValue) else {
            error = "请输入 20 至 400 kg 之间的体重"
            return
        }

        let optionalFields: [(label: String, text: String, range: ClosedRange<Double>)] = [
            ("身高", height, 80...260),
            ("体脂率", bodyFat, 0...100),
            ("体脂肪量", bodyFatMass, 0...200),
            ("骨骼肌量", muscle, 0...150),
            ("BMI", bmi, 5...100),
            ("腰臀比", waistHipRatio, 0.2...3),
            ("内脏脂肪等级", visceral, 0...100),
            ("InBody 评分", score, 0...100),
            ("总体水分", totalBodyWater, 0...150),
            ("蛋白质", protein, 0...100),
            ("矿物质", mineral, 0...30),
            ("去脂体重", fatFreeMass, 0...300),
            ("身体细胞量", bodyCellMass, 0...200),
            ("基础代谢", basalMetabolicRate, 0...10_000),
            ("SMI", smi, 0...30)
        ]
        for field in optionalFields where !validateOptional(
            field.text,
            label: field.label,
            range: field.range
        ) {
            return
        }

        let ageText = age.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ageText.isEmpty,
           (Int(ageText).map { !(0...130).contains($0) } ?? true) {
            error = "年龄需要填写 0 至 130 之间的整数"
            return
        }

        let source: InBodyDataSource = sourceWasUploaded ? initialDraft.source : .manual
        let record = InBodySnapshot(
            date: date,
            heightCm: value(height),
            age: Int(ageText),
            sex: sex.isEmpty ? nil : sex,
            weightKg: weightValue,
            bodyFatKg: value(bodyFatMass),
            bodyFatPercentage: value(bodyFat),
            skeletalMuscleKg: value(muscle),
            bmi: value(bmi),
            visceralFatLevel: value(visceral),
            score: value(score),
            waistHipRatio: value(waistHipRatio),
            totalBodyWaterL: value(totalBodyWater),
            proteinKg: value(protein),
            mineralKg: value(mineral),
            fatFreeMassKg: value(fatFreeMass),
            bodyCellMassKg: value(bodyCellMass),
            basalMetabolicRate: value(basalMetabolicRate),
            smiKgPerM2: value(smi),
            note: note,
            source: source,
            deviceModel: deviceModel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            parserVersion: sourceWasUploaded ? initialDraft.parserVersion : nil,
            ocrConfidence: sourceWasUploaded ? initialDraft.ocrConfidence : nil
        )

        if store.likelyDuplicate(of: record) != nil {
            error = "相近测量时间已有相同体重的记录，请先检查历史记录"
            return
        }

        guard store.add(record) else {
            error = "数据未能保存，请检查测量时间和数值"
            return
        }
        onSaved()
        dismiss()
    }

    private func value(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func validateOptional(
        _ text: String,
        label: String,
        range: ClosedRange<Double>
    ) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        guard let number = value(text), number.isFinite, range.contains(number) else {
            error = "请检查“\(label)”的数字和单位"
            return false
        }
        return true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
