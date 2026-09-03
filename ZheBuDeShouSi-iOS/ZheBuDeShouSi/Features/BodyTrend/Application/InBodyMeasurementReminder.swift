import Foundation

enum InBodyMeasurementInterval: Int, Codable, CaseIterable, Identifiable {
    case twoWeeks = 2
    case fourWeeks = 4
    case sixWeeks = 6
    case eightWeeks = 8
    case twelveWeeks = 12

    var id: Int { rawValue }
    var weekCount: Int { rawValue }

    var title: String {
        switch self {
        case .twoWeeks: return "每 2 周"
        case .fourWeeks: return "每 4 周"
        case .sixWeeks: return "每 6 周"
        case .eightWeeks: return "每 8 周"
        case .twelveWeeks: return "每 12 周"
        }
    }
}

/// User-owned cadence for paper InBody check-ins. The schedule is persisted
/// with trend data, while platform notification APIs stay behind a protocol.
struct InBodyMeasurementSchedule: Codable, Equatable {
    var isEnabled: Bool
    var interval: InBodyMeasurementInterval
    var reminderHour: Int
    var reminderMinute: Int

    static let defaultSchedule = InBodyMeasurementSchedule()

    init(
        isEnabled: Bool = false,
        interval: InBodyMeasurementInterval = .fourWeeks,
        reminderHour: Int = 9,
        reminderMinute: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.interval = interval
        self.reminderHour = min(23, max(0, reminderHour))
        self.reminderMinute = min(59, max(0, reminderMinute))
    }

    func normalized() -> InBodyMeasurementSchedule {
        InBodyMeasurementSchedule(
            isEnabled: isEnabled,
            interval: interval,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
    }

    /// Returns the intended due date rather than silently moving an overdue
    /// date forward. This lets the UI distinguish "upcoming" from "due now".
    func nextDueDate(
        after lastMeasurementDate: Date?,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard isEnabled else { return nil }
        guard let lastMeasurementDate else { return now }
        guard let intervalDate = calendar.date(
            byAdding: .weekOfYear,
            value: interval.weekCount,
            to: lastMeasurementDate
        ) else {
            return nil
        }
        return calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: intervalDate
        ) ?? intervalDate
    }
}

enum InBodyMeasurementDueStatus: Equatable {
    case disabled
    case noMeasurements
    case upcoming(Date)
    case due(Date)
}

struct InBodyMeasurementReminderRequest: Equatable {
    static let defaultIdentifier = "zhebudeshousi.inbody.measurement"

    let identifier: String
    let fireDate: Date
    let title: String
    let body: String

    init(
        identifier: String = Self.defaultIdentifier,
        fireDate: Date,
        title: String = "该记录 InBody 数据了",
        body: String = "上传本次纸质报告，核对后即可查看阶段变化。"
    ) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

/// Application boundary for a future UserNotifications adapter. Views and
/// stores can request a reminder without depending on a platform framework.
protocol InBodyMeasurementReminderScheduling {
    func requestAuthorization() async throws -> Bool
    func schedule(_ request: InBodyMeasurementReminderRequest) async throws
    func cancel(identifier: String) async
}

struct InBodyMeasurementReminderPlanner {
    func request(
        for schedule: InBodyMeasurementSchedule,
        lastMeasurementDate: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> InBodyMeasurementReminderRequest? {
        guard let dueDate = schedule.nextDueDate(
            after: lastMeasurementDate,
            asOf: now,
            calendar: calendar
        ) else {
            return nil
        }

        // Notification frameworks generally reject triggers in the past. The
        // domain still reports the original overdue date through DueStatus.
        let fireDate = dueDate > now
            ? dueDate
            : calendar.date(byAdding: .minute, value: 1, to: now) ?? now
        return InBodyMeasurementReminderRequest(fireDate: fireDate)
    }
}
