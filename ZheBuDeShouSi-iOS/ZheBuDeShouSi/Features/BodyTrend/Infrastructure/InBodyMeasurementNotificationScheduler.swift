import Foundation

#if canImport(UserNotifications)
import UserNotifications
#endif

/// Platform adapter for the application-level reminder boundary. Notification
/// permission is requested only after the user enables periodic measurement.
struct SystemInBodyMeasurementReminderScheduler: InBodyMeasurementReminderScheduling {
    #if canImport(UserNotifications)
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(_ request: InBodyMeasurementReminderRequest) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: request.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(
            UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: trigger
            )
        )
    }

    func cancel(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    #else
    init() {}

    func requestAuthorization() async throws -> Bool { false }
    func schedule(_ request: InBodyMeasurementReminderRequest) async throws {}
    func cancel(identifier: String) async {}
    #endif
}

/// Type erasure keeps SwiftUI independent from UserNotifications and lets
/// previews or focused tests inject a deterministic scheduler.
struct AnyInBodyMeasurementReminderScheduler: InBodyMeasurementReminderScheduling {
    private let authorization: () async throws -> Bool
    private let scheduling: (InBodyMeasurementReminderRequest) async throws -> Void
    private let cancellation: (String) async -> Void

    init<S: InBodyMeasurementReminderScheduling>(_ scheduler: S) {
        authorization = { try await scheduler.requestAuthorization() }
        scheduling = { request in try await scheduler.schedule(request) }
        cancellation = { identifier in await scheduler.cancel(identifier: identifier) }
    }

    func requestAuthorization() async throws -> Bool {
        try await authorization()
    }

    func schedule(_ request: InBodyMeasurementReminderRequest) async throws {
        try await scheduling(request)
    }

    func cancel(identifier: String) async {
        await cancellation(identifier)
    }

    static let live = AnyInBodyMeasurementReminderScheduler(
        SystemInBodyMeasurementReminderScheduler()
    )
}
