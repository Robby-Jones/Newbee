import Foundation
import UserNotifications

/// A local notification to schedule, in plain values so it can cross actors.
struct ScheduledNotification: Sendable, Hashable {
    var identifier: String
    var title: String
    var body: String
    var fireDate: Date
}

/// Whether the parent let Newbee send notifications.
enum NotificationPermission: Sendable, Hashable {
    /// Not asked yet.
    case notDetermined
    case allowed
    /// Turned off in iOS Settings; only the parent can change it there.
    case denied
}

/// The slice of `UNUserNotificationCenter` reminders use, so the scheduler can be tested.
///
/// Requirements are nonisolated and take and return only `Sendable` values, so the live
/// implementation never passes UserNotifications objects across actors.
protocol NotificationClient: Sendable {
    func permission() async -> NotificationPermission
    /// Shows the system prompt if it hasn't been shown; returns whether notifications are allowed.
    func requestPermission() async -> Bool
    /// Removes pending notifications with these identifiers, then adds `notifications`.
    func replace(identifiers: [String], with notifications: [ScheduledNotification]) async
    /// Removes every pending and delivered notification (used by "Delete all data").
    func removeAll() async
}

/// `UNUserNotificationCenter`.
struct SystemNotificationClient: NotificationClient {
    func permission() async -> NotificationPermission {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed // authorized, provisional, ephemeral
        }
    }

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func replace(identifiers: [String], with notifications: [ScheduledNotification]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            let trigger = Self.trigger(for: notification.fireDate)
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// A calendar trigger, so "wait until 6:00" survives the phone sleeping or restarting, that
    /// fires at exactly `fireDate` wherever the phone is.
    static func trigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: triggerComponents(for: fireDate), repeats: false)
    }

    /// `fireDate` as calendar components with their calendar and time zone attached (UTC unless
    /// a test asks for another). Components without a time zone are "floating": iOS reads them
    /// in whatever zone the phone is in when they come due, so after travel a reminder would fire
    /// at the same clock time in the new zone, hours early or late, and a time in the hour that
    /// repeats when clocks fall back could fire an hour early. UTC has neither problem.
    static func triggerComponents(for fireDate: Date, in timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
    }

    func removeAll() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

/// Used under UI tests and in previews: never prompts, never schedules.
struct NoNotificationClient: NotificationClient {
    func permission() async -> NotificationPermission { .denied }
    func requestPermission() async -> Bool { false }
    func replace(identifiers: [String], with notifications: [ScheduledNotification]) async {}
    func removeAll() async {}
}

/// Shows reminders as banners even while Newbee is open.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ForegroundNotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
