import Foundation

enum HealthRecordSource: String, Codable, CaseIterable {
    case manual
    case healthKit
}

struct HealthKitWeightSample: Identifiable, Equatable {
    let id: String
    let date: Date
    let kilograms: Double
}

struct HealthKitWaistSample: Identifiable, Equatable {
    let id: String
    let date: Date
    let centimeters: Double
}

struct HealthKitHabitSample: Identifiable, Equatable {
    let id: String
    let date: Date
    let kind: HabitKind
    let value: Double
    let unit: String
    let note: String
}

enum HealthKitConnectionState: Equatable {
    case unavailable
    case notConnected
    case syncing
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .unavailable: return "当前设备不可用"
        case .notConnected: return "尚未连接"
        case .syncing: return "正在同步"
        case .connected: return "已连接"
        case .failed: return "连接失败"
        }
    }

    var detail: String {
        switch self {
        case .unavailable: return "请在支持 HealthKit 的 iPhone 上使用"
        case .notConnected: return "从 Apple 健康导入体重和腰围"
        case .syncing: return "正在读取最近 90 天的数据"
        case .connected: return "最近一次同步完成"
        case .failed(let message): return message
        }
    }
}

enum BodyMeasurementType: String, Codable, CaseIterable, Identifiable, Hashable {
    case waist
    case hip
    case leftUpperArm
    case rightUpperArm
    case leftThigh
    case rightThigh
    case leftCalf
    case rightCalf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waist: return "腰围"
        case .hip: return "臀围"
        case .leftUpperArm: return "左上臂围"
        case .rightUpperArm: return "右上臂围"
        case .leftThigh: return "左大腿围"
        case .rightThigh: return "右大腿围"
        case .leftCalf: return "左小腿围"
        case .rightCalf: return "右小腿围"
        }
    }

    var shortTitle: String {
        switch self {
        case .leftUpperArm: return "左上臂"
        case .rightUpperArm: return "右上臂"
        case .leftThigh: return "左大腿"
        case .rightThigh: return "右大腿"
        case .leftCalf: return "左小腿"
        case .rightCalf: return "右小腿"
        default: return title
        }
    }
}

struct BodyMeasurementRecord: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var type: BodyMeasurementType
    var valueCm: Double
    var source: HealthRecordSource = .manual
    var note: String = ""
    var externalIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case id, date, type, valueCm, source, note, externalIdentifier
    }

    init(
        id: UUID = UUID(),
        date: Date,
        type: BodyMeasurementType,
        valueCm: Double,
        source: HealthRecordSource = .manual,
        note: String = "",
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.valueCm = valueCm
        self.source = source
        self.note = note
        self.externalIdentifier = externalIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        type = try container.decode(BodyMeasurementType.self, forKey: .type)
        valueCm = try container.decode(Double.self, forKey: .valueCm)
        source = try container.decodeIfPresent(HealthRecordSource.self, forKey: .source) ?? .manual
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        externalIdentifier = try container.decodeIfPresent(String.self, forKey: .externalIdentifier)
    }
}

enum HabitKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case meal
    case exercise
    case sleep
    case water
    case bowelMovement
    case medication
    case menstrualCycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meal: return "饮食"
        case .exercise: return "运动"
        case .sleep: return "睡眠"
        case .water: return "喝水"
        case .bowelMovement: return "排便"
        case .medication: return "吃药"
        case .menstrualCycle: return "生理期"
        }
    }

    var subtitle: String {
        switch self {
        case .meal: return "记录今天吃过的东西"
        case .exercise: return "让身体动起来"
        case .sleep: return "给自己留足休息"
        case .water: return "慢慢补足水分"
        case .bowelMovement: return "关注身体的小信号"
        case .medication: return "按计划完成用药"
        case .menstrualCycle: return "温柔记录身体周期"
        }
    }

    var icon: String {
        switch self {
        case .meal: return "fork.knife"
        case .exercise: return "figure.run"
        case .sleep: return "moon.zzz.fill"
        case .water: return "drop.fill"
        case .bowelMovement: return "leaf.fill"
        case .medication: return "pills.fill"
        case .menstrualCycle: return "heart.circle.fill"
        }
    }

    var tint: String {
        switch self {
        case .meal: return "FDE7ED"
        case .exercise: return "FCEAE5"
        case .sleep: return "EEE9F8"
        case .water: return "E2F3EF"
        case .bowelMovement: return "E8F2DE"
        case .medication: return "FFF0D8"
        case .menstrualCycle: return "FFE1EB"
        }
    }

    var linkedRecordType: RecordType? {
        switch self {
        case .meal: return .meal
        case .water: return .water
        case .exercise: return .sport
        case .sleep, .bowelMovement, .medication, .menstrualCycle: return nil
        }
    }
}

struct HabitRecord: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var kind: HabitKind
    var completed: Bool
    var note: String = ""
    var source: HealthRecordSource = .manual
    var externalIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case id, date, kind, completed, note, source, externalIdentifier
    }

    init(
        id: UUID = UUID(),
        date: Date,
        kind: HabitKind,
        completed: Bool,
        note: String = "",
        source: HealthRecordSource = .manual,
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.completed = completed
        self.note = note
        self.source = source
        self.externalIdentifier = externalIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        kind = try container.decode(HabitKind.self, forKey: .kind)
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try container.decodeIfPresent(HealthRecordSource.self, forKey: .source) ?? .manual
        externalIdentifier = try container.decodeIfPresent(String.self, forKey: .externalIdentifier)
    }
}
