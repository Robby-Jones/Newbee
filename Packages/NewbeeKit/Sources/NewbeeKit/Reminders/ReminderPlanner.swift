import Foundation

/// Hours during which "feed due" reminders wait until morning (docs/UX_SPEC.md §3.10).
///
/// Stored as minutes after local midnight. `start > end` wraps past midnight (22:00–06:00);
/// `start == end` means no quiet time.
public struct QuietHours: Codable, Sendable, Hashable {
    public var startMinute: Int
    public var endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = Self.clamp(startMinute)
        self.endMinute = Self.clamp(endMinute)
    }

    /// 22:00 to 06:00.
    public static let overnight = QuietHours(startMinute: 22 * 60, endMinute: 6 * 60)

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard startMinute != endMinute else { return false }
        let minute = Self.minuteOfDay(date, calendar: calendar)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }

    /// When the quiet time containing `date` ends, or `date` itself if it isn't quiet.
    public func end(after date: Date, calendar: Calendar = .current) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        let dayStart = calendar.startOfDay(for: date)
        let minute = Self.minuteOfDay(date, calendar: calendar)
        // Before `endMinute` today: it ends today. Otherwise (the evening part of a wrapping
        // window) it ends tomorrow.
        let dayOffset = minute < endMinute ? 0 : 1
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: dayStart),
              let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: day)
        else { return date }
        return end
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func clamp(_ minute: Int) -> Int {
        ((minute % 1440) + 1440) % 1440
    }
}

/// What the parent chose in Settings → Reminders. Reminders are opt-in and non-prescriptive.
public struct ReminderSettings: Codable, Sendable, Hashable {
    /// Which moment of the last feed the "feed due" interval counts from.
    public enum Basis: String, Codable, Sendable, CaseIterable, Hashable {
        /// Start to start, the interval clinicians usually mean.
        case start
        /// From when the last feed ended.
        case end
    }

    /// "Feed due" reminder on or off.
    public var isEnabled: Bool
    /// How long after the last feed to remind.
    public var interval: TimeInterval
    public var basis: Basis
    /// `nil` when quiet hours are off.
    public var quietHours: QuietHours?
    /// The "Still feeding?" safety notice for a timer that may have been forgotten.
    public var stillFeedingEnabled: Bool
    /// How long one side (or a pause) runs before "Still feeding?".
    public var stillFeedingThreshold: TimeInterval

    public init(
        isEnabled: Bool = false,
        interval: TimeInterval = 3 * 3600,
        basis: Basis = .start,
        quietHours: QuietHours? = nil,
        stillFeedingEnabled: Bool = true,
        stillFeedingThreshold: TimeInterval = 45 * 60
    ) {
        self.isEnabled = isEnabled
        self.interval = interval
        self.basis = basis
        self.quietHours = quietHours
        self.stillFeedingEnabled = stillFeedingEnabled
        self.stillFeedingThreshold = stillFeedingThreshold
    }

    /// Choices offered for the reminder interval: 1 h 30 min to 5 h in half hours.
    public static let intervalChoices: [TimeInterval] = stride(from: 90, through: 300, by: 30).map { TimeInterval($0 * 60) }
    /// Choices offered for "Still feeding?": 20 min to 1 h 30 min.
    public static let stillFeedingChoices: [TimeInterval] = [20, 30, 45, 60, 90].map { TimeInterval($0 * 60) }

    /// Anything that needs notification permission is on.
    public var needsNotifications: Bool { isEnabled || stillFeedingEnabled }
}

/// The most recent finished feed of any kind, as reminders need it.
public struct LastFeed: Sendable, Hashable {
    public var start: Date
    /// `nil` for a bottle with no duration (it ended when it started).
    public var end: Date?
    public var kind: FeedingKind

    public init(start: Date, end: Date?, kind: FeedingKind) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    /// The newer of the last breastfeed and the last bottle.
    public static func latest(breast: SessionSnapshot?, bottle: BottleEntry?) -> LastFeed? {
        let fromBreast = breast.map {
            LastFeed(start: $0.startedAt, end: $0.endedAt ?? $0.segments.compactMap(\.end).max(), kind: .breast)
        }
        let fromBottle = bottle.map {
            LastFeed(start: $0.startedAt, end: $0.durationSeconds.map($0.startedAt.addingTimeInterval), kind: .bottle)
        }
        switch (fromBreast, fromBottle) {
        case let (b?, f?): return b.start >= f.start ? b : f
        case let (b, f): return b ?? f
        }
    }
}

/// One local notification to schedule.
public struct PlannedReminder: Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable, Hashable {
        /// "It's been 3 h since the last feed."
        case feedDue
        /// "Still feeding? The timer has been on the left side for 45 min."
        case stillFeeding
    }

    public var kind: Kind
    public var fireDate: Date
    /// What the interval was counted from (the last feed's start or end, or the segment's start).
    public var anchor: Date
    /// The side running for `stillFeeding`; `nil` while paused or for `feedDue`.
    public var side: Side?
    /// `true` when a `feedDue` reminder was moved to the end of quiet hours.
    public var deferredByQuietHours: Bool

    public init(kind: Kind, fireDate: Date, anchor: Date, side: Side? = nil, deferredByQuietHours: Bool = false) {
        self.kind = kind
        self.fireDate = fireDate
        self.anchor = anchor
        self.side = side
        self.deferredByQuietHours = deferredByQuietHours
    }

    /// Notification identifier. One per kind, so rescheduling replaces rather than piles up.
    public var identifier: String { Self.identifier(for: kind) }

    public static func identifier(for kind: Kind) -> String { "newbee.reminder.\(kind.rawValue)" }
}

/// Decides which reminders should be pending right now. Pure, so it is tested on Linux.
///
/// Rules:
/// - **Feed due** fires `interval` after the last feed's start (or end), only when reminders are
///   on, no breastfeed is running, and the time is still ahead. In quiet hours it waits until
///   they end. Overdue reminders are not sent late.
/// - **Still feeding?** fires `stillFeedingThreshold` after the running side started (or the
///   pause began). It ignores quiet hours: a timer left running overnight is what it's for.
public struct ReminderPlanner: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func plan(settings: ReminderSettings, lastFeed: LastFeed?, active: SessionSnapshot?, now: Date) -> [PlannedReminder] {
        var reminders: [PlannedReminder] = []
        if let active, active.status != .completed {
            if settings.stillFeedingEnabled, let still = stillFeeding(active, threshold: settings.stillFeedingThreshold, now: now) {
                reminders.append(still)
            }
        } else if settings.isEnabled, let lastFeed, let due = feedDue(settings: settings, lastFeed: lastFeed, now: now) {
            reminders.append(due)
        }
        return reminders
    }

    func feedDue(settings: ReminderSettings, lastFeed: LastFeed, now: Date) -> PlannedReminder? {
        let anchor: Date = switch settings.basis {
        case .start: lastFeed.start
        case .end: lastFeed.end ?? lastFeed.start
        }
        var fire = anchor.addingTimeInterval(settings.interval)
        var deferred = false
        if let quiet = settings.quietHours, quiet.contains(fire, calendar: calendar) {
            fire = quiet.end(after: fire, calendar: calendar)
            deferred = true
        }
        guard fire > now else { return nil }
        return PlannedReminder(kind: .feedDue, fireDate: fire, anchor: anchor, deferredByQuietHours: deferred)
    }

    func stillFeeding(_ session: SessionSnapshot, threshold: TimeInterval, now: Date) -> PlannedReminder? {
        var anchor: Date
        let side: Side?
        if session.status == .active, let open = session.openSegment {
            anchor = open.start
            side = open.side
        } else {
            // Paused: the pause began when the last segment closed.
            anchor = session.segments.compactMap(\.end).max() ?? session.startedAt
            side = nil
        }
        // After "Keep going" on the recovery sheet, count again from that answer.
        if let acknowledged = session.recoveryAcknowledgedAt, acknowledged > anchor {
            anchor = acknowledged
        }
        let fire = anchor.addingTimeInterval(threshold)
        guard fire > now else { return nil }
        return PlannedReminder(kind: .stillFeeding, fireDate: fire, anchor: anchor, side: side)
    }
}
