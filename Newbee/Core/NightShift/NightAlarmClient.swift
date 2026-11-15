import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// "Ring as alarm" for the parent on duty (docs/NIGHT_SHIFT.md): the feed reminder as a real
/// alarm that rings in Silent mode and through a Focus. Needs iOS 26 (AlarmKit); on older
/// versions the reminder stays a normal notification.
protocol NightAlarmClient: Sendable {
    /// Whether this iPhone can ring alarms for apps at all.
    var isSupported: Bool { get }
    /// Shows the system prompt if it hasn't been shown; returns whether alarms are allowed.
    func requestPermission() async -> Bool
    /// Replaces Newbee's pending alarm with `alarm`; `nil` just cancels it. Returns whether an
    /// alarm is now set, so the caller knows to fall back to a notification.
    func replace(with alarm: ScheduledNotification?) async -> Bool
}

/// Used in tests, previews and under UI tests: never prompts, never rings.
struct NoNightAlarmClient: NightAlarmClient {
    var isSupported: Bool { false }
    func requestPermission() async -> Bool { false }
    func replace(with alarm: ScheduledNotification?) async -> Bool { false }
}

/// AlarmKit.
struct SystemNightAlarmClient: NightAlarmClient {
    private static let alarmIDKey = "nightShift.alarmID"

    var isSupported: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    func requestPermission() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        }
        #endif
        return false
    }

    func replace(with alarm: ScheduledNotification?) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await Self.replaceAlarm(with: alarm)
        }
        #endif
        return false
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func replaceAlarm(with alarm: ScheduledNotification?) async -> Bool {
        let manager = AlarmManager.shared
        let defaults = UserDefaults.standard
        // One alarm at a time: the last one Newbee set goes first.
        if let stored = defaults.string(forKey: alarmIDKey), let id = UUID(uuidString: stored) {
            try? manager.cancel(id: id)
            defaults.removeObject(forKey: alarmIDKey)
        }
        guard let alarm, manager.authorizationState == .authorized else { return false }
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: alarm.title),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        )
        let attributes = AlarmAttributes<FeedAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: FeedAlarmMetadata(),
            tintColor: .indigo
        )
        let id = UUID()
        do {
            _ = try await manager.schedule(id: id, configuration: .alarm(schedule: .fixed(alarm.fireDate), attributes: attributes))
            defaults.set(id.uuidString, forKey: alarmIDKey)
            return true
        } catch {
            return false
        }
    }
    #endif
}

#if canImport(AlarmKit)
/// AlarmKit wants a metadata type; the feed alarm has nothing to add.
@available(iOS 26.0, *)
struct FeedAlarmMetadata: AlarmMetadata {}
#endif
