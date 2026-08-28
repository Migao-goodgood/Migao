import Foundation
import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "首页"
    case trend = "趋势"
    case habits = "习惯"
    case mine = "我的"
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
        case .weight: return "kg"
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

    var loss: Double {
        switch self {
        case .week: return 0.7
        case .month: return 1.8
        case .quarter: return 3.4
        }
    }
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
    static let goalWeightRange = 20.0...300.0

    @Published var weight: Double = 58.6
    @Published private(set) var goalWeight: Double = 54.0
    @Published var water: Int = 1200
    @Published var records: [WeightRecord] = []
    @Published var logs: [ActivityLog] = []

    private let storageKey = "zhebudeshousi.appState"

    init() {
        let calendar = Calendar.current
        let today = Date()
        records = [
            WeightRecord(date: today, weight: 58.6, note: "晨起空腹", change: -0.2),
            WeightRecord(date: calendar.date(byAdding: .day, value: -1, to: today) ?? today, weight: 58.8, note: "晨起空腹", change: -0.1),
            WeightRecord(date: calendar.date(byAdding: .day, value: -2, to: today) ?? today, weight: 58.9, note: "晨起空腹", change: -0.2),
            WeightRecord(date: calendar.date(byAdding: .day, value: -3, to: today) ?? today, weight: 59.1, note: "晚餐后", change: -0.2)
        ]
        logs = [
            ActivityLog(kind: .meal, title: "鸡胸肉沙拉", date: today, amount: "420 kcal", note: "午餐 · 12:18"),
            ActivityLog(kind: .water, title: "补充水分", date: today, amount: "300 ml", note: "上午 · 10:35"),
            ActivityLog(kind: .sport, title: "公园散步", date: today, amount: "32 分钟", note: "运动 · 09:10")
        ]
        load()
    }

    var startWeight: Double { 62.0 }
    /// Gap = 当日体重 - 目标体重。正数代表还高于目标，负数代表已经低于目标。
    var weightGap: Double { weight - goalWeight }
    var goalProgress: Double {
        let totalChange = goalWeight - startWeight
        guard abs(totalChange) > 0.05 else { return abs(weight - goalWeight) <= 0.05 ? 1 : 0 }
        return min(1, max(0, (weight - startWeight) / totalChange))
    }

    func weightTone(_ value: Double) -> Color {
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
        goalWeight = (value * 10).rounded() / 10
        save()
        return true
    }

    func addWeight(_ value: Double, note: String) {
        let difference = value - weight
        weight = value
        records.insert(WeightRecord(date: .now, weight: value, note: note.isEmpty ? "刚刚记录" : note, change: difference), at: 0)
        logs.insert(ActivityLog(kind: .weight, title: "体重记录", date: .now, amount: String(format: "%.1f kg", value), note: note.isEmpty ? timeLabel() : note), at: 0)
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

    private func timeLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: .now) + " · 刚刚"
    }

    private struct Snapshot: Codable {
        var weight: Double
        var goalWeight: Double?
        var water: Int
        var records: [WeightRecord]
        var logs: [ActivityLog]
    }

    private func save() {
        let snapshot = Snapshot(weight: weight, goalWeight: goalWeight, water: water, records: records, logs: logs)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        weight = snapshot.weight
        goalWeight = snapshot.goalWeight ?? goalWeight
        water = snapshot.water
        records = snapshot.records
        logs = snapshot.logs
    }
}

extension Color {
    static let pagePink = Color(hex: "F4F7FB")
    static let panelPink = Color(hex: "E7EDF3")
    static let strawberry = Color(hex: "1B2B38")
    static let softPink = Color(hex: "D1DCE5")
    static let warmText = Color(hex: "1F2A33")
    static let mutedText = Color(hex: "74818B")
    static let mintGreen = Color(hex: "67AF97")
    static let mintPale = Color(hex: "E5F1ED")
    static let lavenderPale = Color(hex: "E8EEF3")
    static let ink = Color(hex: "172531")
    static let inkSoft = Color(hex: "354B5A")
    static let platinum = Color(hex: "B9C4CD")
    static let platinumDeep = Color(hex: "6D7E8A")
    static let platinumLight = Color(hex: "E6EDF2")
    static let platinumPale = Color(hex: "F4F7FB")
    static let waterAccent = Color(hex: "5D8298")
    static let waterAccentPale = Color(hex: "E7F0F4")

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
