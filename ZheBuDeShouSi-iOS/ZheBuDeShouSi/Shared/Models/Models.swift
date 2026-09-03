import Foundation
import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "首页"
    case diet = "饮食"
    case trend = "趋势"
    case mine = "我的"
}

/// User-facing body-weight units. Values are stored canonically in kilograms
/// so changing the display unit never changes historical measurements.
enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kilograms = "公斤"
    case jin = "斤"

    static let minimumKilograms = 20.0
    static let maximumKilograms = 300.0
    static let stepKilograms = 0.1

    var id: String { rawValue }

    var displayMultiplier: Double {
        self == .kilograms ? 1 : 2
    }

    var displayDecimals: Int {
        1
    }

    var tickCount: Int {
        Int(((Self.maximumKilograms - Self.minimumKilograms) / Self.stepKilograms).rounded()) + 1
    }

    var rulerMajorTickInterval: Int {
        self == .kilograms ? 10 : 5
    }

    func isMajorRulerTick(_ index: Int) -> Bool {
        index.isMultiple(of: rulerMajorTickInterval)
    }

    func isMediumRulerTick(_ index: Int) -> Bool {
        self == .kilograms && !isMajorRulerTick(index) && index.isMultiple(of: 5)
    }

    func displayValue(fromKilograms kilograms: Double) -> Double {
        kilograms * displayMultiplier
    }

    func kilograms(fromDisplayValue value: Double) -> Double {
        value / displayMultiplier
    }

    func tickIndex(forKilograms kilograms: Double) -> Int {
        let raw = ((kilograms - Self.minimumKilograms) / Self.stepKilograms).rounded()
        return min(tickCount - 1, max(0, Int(raw)))
    }

    func kilograms(forTick index: Int) -> Double {
        let clamped = min(tickCount - 1, max(0, index))
        return Self.minimumKilograms + Double(clamped) * Self.stepKilograms
    }

    func formattedValue(fromKilograms kilograms: Double) -> String {
        let value = displayValue(fromKilograms: kilograms)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = displayDecimals
        formatter.maximumFractionDigits = displayDecimals
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.*f", displayDecimals, value)
    }

    func formatted(fromKilograms kilograms: Double, includeUnit: Bool = true) -> String {
        let value = formattedValue(fromKilograms: kilograms)
        return includeUnit ? "\(value) \(rawValue)" : value
    }

    func rulerLabel(forTick index: Int) -> String {
        let kilograms = kilograms(forTick: index)
        return String(format: "%.0f", displayValue(fromKilograms: kilograms))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storedValue = try container.decode(String.self)
        switch storedValue.lowercased() {
        case "kg", "kilograms", "公斤":
            self = .kilograms
        case "g", "grams", "jin", "斤":
            // Older snapshots used `g`; the user's selected secondary unit
            // migrates to the new secondary display without touching weights.
            self = .jin
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported stored weight unit: \(storedValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self == .kilograms ? "kg" : "jin")
    }
}

enum RecordType: String, Codable, CaseIterable {
    case meal, water, sport, weight

    var title: String {
        switch self {
        case .meal: return "记录饮食"
        case .water: return "记录饮水"
        case .sport: return "记录运动"
        case .weight: return "记录体重"
        }
    }

    var nameLabel: String {
        switch self {
        case .meal: return "吃了什么"
        case .water: return "饮品名称"
        case .sport: return "运动项目"
        case .weight: return "当前体重"
        }
    }

    var namePlaceholder: String {
        switch self {
        case .meal: return "例如：鸡胸肉沙拉"
        case .water: return "例如：温水"
        case .sport: return "例如：快走"
        case .weight: return ""
        }
    }

    var amountLabel: String {
        switch self {
        case .meal: return "大约热量"
        case .water: return "饮水量"
        case .sport: return "运动时长"
        case .weight: return "当前体重"
        }
    }

    var amountPlaceholder: String {
        switch self {
        case .meal: return "420"
        case .water: return "300"
        case .sport: return "30"
        case .weight: return ""
        }
    }

    var unit: String {
        switch self {
        case .meal: return "kcal"
        case .water: return "ml"
        case .sport: return "分钟"
        case .weight: return "公斤"
        }
    }

    var mascot: MascotKind {
        switch self {
        case .meal: return .berryBunny
        case .water: return .puddingBear
        case .sport: return .mintMochi
        case .weight: return .cloudKitty
        }
    }
}

enum TrendPeriod: String, CaseIterable {
    case week = "7天"
    case month = "30天"
    case quarter = "3个月"
}

enum MascotKind {
    case berryBunny, puddingBear, mintMochi, cloudKitty
}

struct ActivityLog: Identifiable, Codable {
    var id = UUID()
    var kind: RecordType
    var title: String
    var date: Date
    var amount: String
    var note: String
}

struct WeightRecord: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var weight: Double
    var note: String
    var change: Double
    var source: HealthRecordSource = .manual
    var externalIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case id, date, weight, note, change, source, externalIdentifier
    }

    init(
        id: UUID = UUID(),
        date: Date,
        weight: Double,
        note: String,
        change: Double,
        source: HealthRecordSource = .manual,
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.date = date
        self.weight = weight
        self.note = note
        self.change = change
        self.source = source
        self.externalIdentifier = externalIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        weight = try container.decode(Double.self, forKey: .weight)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        change = try container.decodeIfPresent(Double.self, forKey: .change) ?? 0
        source = try container.decodeIfPresent(HealthRecordSource.self, forKey: .source) ?? .manual
        externalIdentifier = try container.decodeIfPresent(String.self, forKey: .externalIdentifier)
    }
}

@MainActor
final class AppState: ObservableObject {
    static let storageKey = "zhebudeshousi.appState"
    static let goalWeightRange = WeightUnit.minimumKilograms...WeightUnit.maximumKilograms

    @Published var weight: Double = 0
    @Published private(set) var goalWeight: Double = 0
    @Published var water: Int = 0
    @Published var records: [WeightRecord] = []
    @Published var logs: [ActivityLog] = []
    @Published private(set) var avatarData: Data?
    @Published private(set) var weightUnit: WeightUnit = .kilograms

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var currentWeight: Double? {
        records.max(by: { $0.date < $1.date })?.weight
            ?? (Self.goalWeightRange.contains(weight) ? weight : nil)
    }

    var startWeight: Double? {
        records.min(by: { $0.date < $1.date })?.weight ?? currentWeight
    }

    var hasWeightData: Bool { currentWeight != nil }
    var hasConfiguredGoal: Bool { Self.goalWeightRange.contains(goalWeight) }

    var chartGoalWeight: Double {
        hasConfiguredGoal ? goalWeight : (currentWeight ?? WeightUnit.minimumKilograms)
    }

    /// Gap = 当日体重 - 目标体重。正数代表还高于目标，负数代表已经低于目标。
    var weightGap: Double? {
        guard let currentWeight, hasConfiguredGoal else { return nil }
        return currentWeight - goalWeight
    }

    var goalProgress: Double? {
        guard let startWeight, let currentWeight, hasConfiguredGoal else { return nil }
        let totalChange = goalWeight - startWeight
        guard abs(totalChange) > 0.05 else { return abs(currentWeight - goalWeight) <= 0.05 ? 1 : 0 }
        return min(1, max(0, (currentWeight - startWeight) / totalChange))
    }

    func weightTone(_ value: Double) -> Color {
        guard hasConfiguredGoal else { return .waterAccent }
        let distance = value - goalWeight
        if distance <= 0 { return .mintGreen }
        if distance < 1.5 { return Color(hex: "E5A173") }
        if distance < 3 { return Color(hex: "EA927B") }
        if distance < 4.5 { return Color(hex: "ED7E80") }
        if distance < 6 { return Color(hex: "ED6E83") }
        if distance < 8 { return Color(hex: "E65F7D") }
        return Color(hex: "D94F70")
    }

    @discardableResult
    func updateGoalWeight(_ value: Double) -> Bool {
        guard value.isFinite, Self.goalWeightRange.contains(value) else { return false }
        goalWeight = (value / WeightUnit.stepKilograms).rounded() * WeightUnit.stepKilograms
        save()
        return true
    }

    func updateWeightUnit(_ unit: WeightUnit) {
        guard weightUnit != unit else { return }
        weightUnit = unit
        save()
    }

    func formattedWeight(_ kilograms: Double, includeUnit: Bool = true) -> String {
        weightUnit.formatted(fromKilograms: kilograms, includeUnit: includeUnit)
    }

    func addWeight(_ value: Double, date: Date = .now, note: String) {
        guard value.isFinite, Self.goalWeightRange.contains(value) else { return }

        let calendar = Calendar.current
        let normalizedValue = (value / WeightUnit.stepKilograms).rounded() * WeightUnit.stepKilograms
        let previous = records
            .filter { $0.date < date }
            .max(by: { $0.date < $1.date })
        let difference = normalizedValue - (previous?.weight ?? currentWeight ?? normalizedValue)
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        records.append(
            WeightRecord(
                date: date,
                weight: normalizedValue,
                note: cleanedNote.isEmpty ? "刚刚记录" : cleanedNote,
                change: difference
            )
        )
        records.sort { $0.date > $1.date }

        // Rebuild neighboring deltas so a backfilled day behaves like any
        // other chronological record in the trend and calendar.
        var chronological = records.sorted { $0.date < $1.date }
        for index in chronological.indices {
            chronological[index].change = index == chronological.startIndex
                ? 0
                : chronological[index].weight - chronological[chronological.index(before: index)].weight
        }
        records = chronological.sorted { $0.date > $1.date }
        weight = records.first?.weight ?? weight

        logs.insert(
            ActivityLog(
                kind: .weight,
                title: "体重记录",
                date: date,
                amount: weightUnit.formatted(fromKilograms: normalizedValue),
                note: cleanedNote.isEmpty ? timeLabel(for: date, calendar: calendar) : cleanedNote
            ),
            at: 0
        )
        logs.sort { $0.date > $1.date }
        save()
    }

    @discardableResult
    func importHealthKitWeights(_ samples: [HealthKitWeightSample]) -> Int {
        let importedRecords = samples.compactMap { sample -> WeightRecord? in
            guard sample.kilograms.isFinite, Self.goalWeightRange.contains(sample.kilograms),
                  !records.contains(where: { $0.externalIdentifier == sample.id }) else { return nil }
            return WeightRecord(
                date: sample.date,
                weight: sample.kilograms,
                note: "来自 Apple 健康",
                change: 0,
                source: .healthKit,
                externalIdentifier: sample.id
            )
        }

        guard !importedRecords.isEmpty else { return 0 }
        records.append(contentsOf: importedRecords)
        records.sort { $0.date > $1.date }
        for index in records.indices {
            guard index + 1 < records.count else { continue }
            records[index].change = records[index].weight - records[index + 1].weight
        }
        weight = records.first?.weight ?? weight
        save()
        return importedRecords.count
    }

    func addActivity(type: RecordType, name: String, amount: String, note: String) {
        let title = name.isEmpty ? type.title : name
        let displayNote = note.isEmpty ? timeLabel() : note
        logs.insert(ActivityLog(kind: type, title: title, date: .now, amount: "\(amount) \(type.unit)", note: displayNote), at: 0)
        if type == .water, let value = Int(amount) { water += value }
        save()
    }

    func updateAvatar(_ data: Data?) {
        avatarData = data
        save()
    }

    private func timeLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: .now) + " · 刚刚"
    }

    private struct Snapshot: Codable {
        var weight: Double?
        var goalWeight: Double?
        var water: Int
        var records: [WeightRecord]
        var logs: [ActivityLog]
        var avatarData: Data?
        var weightUnit: WeightUnit?

        enum CodingKeys: String, CodingKey {
            case weight, goalWeight, water, records, logs, avatarData, weightUnit
        }

        init(
            weight: Double?,
            goalWeight: Double?,
            water: Int,
            records: [WeightRecord],
            logs: [ActivityLog],
            avatarData: Data?,
            weightUnit: WeightUnit?
        ) {
            self.weight = weight
            self.goalWeight = goalWeight
            self.water = water
            self.records = records
            self.logs = logs
            self.avatarData = avatarData
            self.weightUnit = weightUnit
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            weight = try container.decodeIfPresent(Double.self, forKey: .weight)
            goalWeight = try container.decodeIfPresent(Double.self, forKey: .goalWeight)
            water = try container.decodeIfPresent(Int.self, forKey: .water) ?? 0
            records = try container.decodeIfPresent([WeightRecord].self, forKey: .records) ?? []
            logs = try container.decodeIfPresent([ActivityLog].self, forKey: .logs) ?? []
            avatarData = try container.decodeIfPresent(Data.self, forKey: .avatarData)
            weightUnit = try container.decodeIfPresent(WeightUnit.self, forKey: .weightUnit)
        }
    }

    private func save() {
        let snapshot = Snapshot(
            weight: currentWeight,
            goalWeight: hasConfiguredGoal ? goalWeight : nil,
            water: water,
            records: records,
            logs: logs,
            avatarData: avatarData,
            weightUnit: weightUnit
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        records = snapshot.records
            .filter { $0.weight.isFinite && Self.goalWeightRange.contains($0.weight) }
            .sorted { $0.date > $1.date }
        let restoredWeight = records.first?.weight ?? snapshot.weight
        weight = restoredWeight.flatMap { Self.goalWeightRange.contains($0) ? $0 : nil } ?? 0
        goalWeight = snapshot.goalWeight.flatMap { Self.goalWeightRange.contains($0) ? $0 : nil } ?? 0
        water = max(0, snapshot.water)
        logs = snapshot.logs.sorted { $0.date > $1.date }
        avatarData = snapshot.avatarData
        weightUnit = snapshot.weightUnit ?? .kilograms
    }

    private func timeLabel(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "M月d日"
        return formatter.string(from: date) + " · 刚刚"
    }
}

/// The single color scale shared by the home journey rail and weight calendar.
/// Position zero is always the recorded starting point (pink), while position
/// one is always the configured goal (blue), regardless of numeric direction.
enum WeightJourneyPalette {
    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red / 255, green: green / 255, blue: blue / 255)
        }
    }

    private static let startRGB = RGB(red: 245, green: 141, blue: 174)
    private static let goalRGB = RGB(red: 112, green: 200, blue: 218)
    private static let inkRGB = RGB(red: 51, green: 44, blue: 56)

    static let startColor = startRGB.color
    static let goalColor = goalRGB.color

    static var gradient: LinearGradient {
        LinearGradient(colors: [startColor, goalColor], startPoint: .leading, endPoint: .trailing)
    }

    static func position(weight: Double, startWeight: Double, goalWeight: Double) -> Double {
        guard weight.isFinite, startWeight.isFinite, goalWeight.isFinite else { return 0.5 }
        let span = goalWeight - startWeight
        guard abs(span) > 0.000_1 else {
            return weight <= goalWeight + WeightUnit.stepKilograms / 2 ? 1 : 0
        }
        return clamp((weight - startWeight) / span)
    }

    static func tone(weight: Double, startWeight: Double, goalWeight: Double) -> Color {
        tone(at: position(weight: weight, startWeight: startWeight, goalWeight: goalWeight))
    }

    static func textTone(weight: Double, startWeight: Double, goalWeight: Double) -> Color {
        let value = position(weight: weight, startWeight: startWeight, goalWeight: goalWeight)
        return interpolate(from: interpolate(from: startRGB, to: goalRGB, amount: value), to: inkRGB, amount: 0.45).color
    }

    private static func tone(at position: Double) -> Color {
        interpolate(from: startRGB, to: goalRGB, amount: position).color
    }

    private static func interpolate(from start: RGB, to end: RGB, amount: Double) -> RGB {
        let value = clamp(amount)
        return RGB(
            red: start.red + (end.red - start.red) * value,
            green: start.green + (end.green - start.green) * value,
            blue: start.blue + (end.blue - start.blue) * value
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

extension Color {
    static let pagePink = Color(hex: "FFF8FA")
    static let panelPink = Color(hex: "FFE7EF")
    static let strawberry = Color(hex: "3C3040")
    static let softPink = Color(hex: "FFD1DE")
    static let warmText = Color(hex: "3C3040")
    static let mutedText = Color(hex: "9B8490")
    static let mintGreen = Color(hex: "67AF97")
    static let mintPale = Color(hex: "E4F8F2")
    static let lavenderPale = Color(hex: "F0EBFF")
    static let ink = Color(hex: "332C38")
    static let inkSoft = Color(hex: "5D4F61")
    static let platinum = Color(hex: "D8CBD2")
    static let platinumDeep = Color(hex: "9A8290")
    static let platinumLight = Color(hex: "F6E9EE")
    static let platinumPale = Color(hex: "FFF8FA")
    static let waterAccent = Color(hex: "63B7D0")
    static let waterAccentPale = Color(hex: "E3F6FA")
    static let jellyPink = WeightJourneyPalette.startColor
    static let jellyBlue = WeightJourneyPalette.goalColor
    static let jellyMint = Color(hex: "7FD1B7")

    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red = Double((number >> 16) & 0xff) / 255
        let green = Double((number >> 8) & 0xff) / 255
        let blue = Double(number & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension View {
    func kawaiiCard(radius: CGFloat = 25) -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.95), lineWidth: 2))
            .shadow(color: Color.platinum.opacity(0.52), radius: 0, x: 0, y: 7)
    }

    func roundedFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(.system(size: size, weight: weight, design: .default))
    }
}
