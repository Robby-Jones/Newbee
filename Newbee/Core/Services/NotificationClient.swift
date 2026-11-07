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
            // A wall-clock trigger, so "wait until 6:00" survives the phone sleeping or restarting.
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: notification.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
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
