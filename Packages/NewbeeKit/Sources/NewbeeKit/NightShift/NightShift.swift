import Foundation

/// One night shift on a shared log (docs/NIGHT_SHIFT.md): which parent is on duty, and until when.
///
/// A log has one shift record. Starting a shift, taking over and ending early all replace it,
/// and it syncs to the other parent like a feed does, so both phones agree on who is on duty.
public struct NightShift: SyncPayload, Hashable {
    public static let kind = SyncRecordKind.nightShift
    /// The record name of the one shift record.
    public static let recordID = "current"

    /// The parent on duty: an opaque ID that is the same on all of that parent's devices.
    public var onDuty: String
    public var startedAt: Date
    /// The morning time the shift ends by itself.
    public var endsAt: Date
    /// Set when the parent on duty ends the shift before `endsAt`.
    public var endedAt: Date?
    /// When this record was last changed; the later change wins when both phones changed it.
    public var changedAt: Date

    public init(onDuty: String, startedAt: Date, endsAt: Date, endedAt: Date? = nil, changedAt: Date) {
        self.onDuty = onDuty
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.endedAt = endedAt
        self.changedAt = changedAt
    }

    public var key: SyncKey { SyncKey(kind: .nightShift, id: Self.recordID) }

    /// When the shift is over: the morning time, or earlier if it was ended by hand.
    public var end: Date {
        guard let endedAt else { return endsAt }
        return min(endedAt, endsAt)
    }

    /// A shift is never created ahead of time, so it runs from the moment it exists until its end.
    public func isRunning(at now: Date) -> Bool {
        now < end
    }

    /// What this shift means for the parent `me` right now.
    public func duty(for me: String, at now: Date) -> NightDuty {
        guard isRunning(at: now) else { return .none }
        return onDuty == me ? .onDuty(until: end) : .offDuty(until: end)
    }

    // MARK: - Changes

    /// "Start on-call": a new shift from now until the next `schedule.morningMinute`.
    public static func starting(for me: String, at now: Date, schedule: NightShiftSchedule, calendar: Calendar = .current) -> NightShift {
        NightShift(onDuty: me, startedAt: now, endsAt: schedule.morning(after: now, calendar: calendar), changedAt: now)
    }

    /// "Take over": the other parent is on duty from now, until the same morning time.
    public func takenOver(by me: String, at now: Date) -> NightShift {
        NightShift(onDuty: me, startedAt: now, endsAt: endsAt, changedAt: now)
    }

    /// "End shift": over now instead of in the morning.
    public func ended(at now: Date) -> NightShift {
        var shift = self
        shift.endedAt = now
        shift.changedAt = now
        return shift
    }
}

/// A parent's part in the night, as reminders need it.
public enum NightDuty: Sendable, Hashable {
    /// No shift is running: reminders work as set in Settings.
    case none
    /// This parent is on duty: feed reminders ring here, quiet hours or not.
    case onDuty(until: Date)
    /// The other parent is on duty: this phone stays quiet until the shift ends.
    case offDuty(until: Date)
}

/// When on-call shifts start and end (shown as "On-Call Shift" in the app).
public struct NightShiftSchedule: Codable, Sendable, Hashable {
    /// Minutes after local midnight from when Home offers "Start on-call". 6:00 PM unless changed
    /// in Settings.
    public var eveningMinute: Int
    /// Minutes after local midnight when a shift ends by itself. 7:00 AM unless changed in Settings.
    public var morningMinute: Int

    public init(
        eveningMinute: Int = NightShiftSchedule.defaultEveningMinute,
        morningMinute: Int = NightShiftSchedule.defaultMorningMinute
    ) {
        self.eveningMinute = min(max(eveningMinute, 0), 1439)
        self.morningMinute = min(max(morningMinute, 0), 1439)
    }

    public static let defaultMorningMinute = 7 * 60
    public static let defaultEveningMinute = 18 * 60

    /// The shift window: from the start time until the end time.
    private var night: QuietHours {
        QuietHours(startMinute: eveningMinute, endMinute: morningMinute)
    }

    /// Whether a shift can be started now: only in the evening and at night, so the offer isn't
    /// on Home all day.
    public func offersStart(at now: Date, calendar: Calendar = .current) -> Bool {
        night.contains(now, calendar: calendar)
    }

    /// The next time the clock shows the morning time.
    public func morning(after now: Date, calendar: Calendar = .current) -> Date {
        let time = DateComponents(hour: morningMinute / 60, minute: morningMinute % 60, second: 0)
        return calendar.nextDate(after: now, matching: time, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(12 * 3600)
    }
}

/// The one Night Shift card Home shows, if any. Pure, so the rules are tested on Linux.
public enum NightShiftCard: Sendable, Hashable {
    /// Evening, nobody on duty: "Start on-call".
    case offerStart
    /// This parent is on duty.
    case onDuty(until: Date)
    /// The other parent is on duty.
    case partnerOnDuty(until: Date)
    /// The other parent's shift is over: "While you slept".
    case summary(NightShift)

    /// How long after a shift the summary stays if it isn't dismissed.
    public static let summaryLifetime: TimeInterval = 12 * 3600

    /// - Parameters:
    ///   - me: This parent's ID, or `nil` while iCloud hasn't said who they are yet.
    ///   - dismissedShiftStart: `startedAt` of the shift whose summary the parent dismissed.
    public static func current(
        shift: NightShift?,
        me: String?,
        now: Date,
        schedule: NightShiftSchedule,
        dismissedShiftStart: Date? = nil,
        calendar: Calendar = .current
    ) -> NightShiftCard? {
        if let shift, let me {
            switch shift.duty(for: me, at: now) {
            case .onDuty(let until):
                return .onDuty(until: until)
            case .offDuty(let until):
                return .partnerOnDuty(until: until)
            case .none:
                let isFresh = now < shift.end.addingTimeInterval(summaryLifetime)
                if shift.onDuty != me, isFresh, dismissedShiftStart != shift.startedAt {
                    return .summary(shift)
                }
            }
        } else if let shift, shift.isRunning(at: now) {
            // Someone is on duty, but this phone can't tell who yet. Say nothing rather than guess.
            return nil
        }
        return schedule.offersStart(at: now, calendar: calendar) ? .offerStart : nil
    }
}

/// What happened during a shift, for the parent who slept through it.
public struct NightSummary: Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var breastfeeds: Int
    /// Total nursing time, pauses excluded.
    public var nursing: TimeInterval
    public var bottles: Int
    public var bottleML: Double
    /// When the last feed of the shift started.
    public var lastFeedStart: Date?

    public var feeds: Int { breastfeeds + bottles }

    /// Counts the finished feeds that started during the shift. Pumping isn't a feed.
    public init(shift: NightShift, feeds: [FeedEntry]) {
        start = shift.startedAt
        end = shift.end
        let during = feeds.filter { $0.start >= shift.startedAt && $0.start < shift.end }
        let breast = during.filter { $0.kind == .breast }
        let bottle = during.filter { $0.kind == .bottle }
        breastfeeds = breast.count
        nursing = breast.reduce(0) { $0 + $1.breastDuration }
        bottles = bottle.count
        bottleML = bottle.reduce(0) { $0 + $1.bottleML }
        lastFeedStart = during.map(\.start).max()
    }
}
