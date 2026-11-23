import Foundation
import Testing
@testable import NewbeeKit

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-11-07 00:00 UTC.
private let midnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 7))!

private func at(_ hour: Double) -> Date { midnight.addingTimeInterval(hour * 3600) }

private let planner = ReminderPlanner(calendar: utc)

private func breastfeed(start: Date, end: Date) -> SessionSnapshot {
    SessionSnapshot(status: .completed, segments: [Segment(side: .left, start: start, end: end)], startedAt: start, endedAt: end)
}

@Suite("Quiet hours")
struct QuietHoursTests {
    @Test func wrapsPastMidnight() {
        let quiet = QuietHours.overnight
        #expect(quiet.contains(at(23), calendar: utc))
        #expect(quiet.contains(at(2), calendar: utc))
        #expect(!quiet.contains(at(6), calendar: utc))
        #expect(!quiet.contains(at(21.99), calendar: utc))
        // Evening part ends tomorrow morning, the early part ends this morning.
        #expect(quiet.end(after: at(23), calendar: utc) == at(30))
        #expect(quiet.end(after: at(2), calendar: utc) == at(6))
        #expect(quiet.end(after: at(12), calendar: utc) == at(12))
    }

    @Test func sameDayWindowAndEmptyWindow() {
        let nap = QuietHours(startMinute: 13 * 60, endMinute: 15 * 60)
        #expect(nap.contains(at(14), calendar: utc))
        #expect(!nap.contains(at(15), calendar: utc))
        #expect(nap.end(after: at(14), calendar: utc) == at(15))
        #expect(!QuietHours(startMinute: 600, endMinute: 600).contains(at(10), calendar: utc))
    }

    @Test func normalisesOutOfRangeMinutes() {
        #expect(QuietHours(startMinute: -60, endMinute: 1500).startMinute == 23 * 60)
        #expect(QuietHours(startMinute: -60, endMinute: 1500).endMinute == 60)
    }
}

@Suite("Reminder planner")
struct ReminderPlannerTests {
    let on = ReminderSettings(isEnabled: true, interval: 3 * 3600)

    @Test func feedDueCountsFromTheLastStart() {
        let last = LastFeed(start: at(9), end: at(9.5), kind: .breast)
        let plan = planner.plan(settings: on, lastFeed: last, active: nil, now: at(10))
        #expect(plan == [PlannedReminder(kind: .feedDue, fireDate: at(12), anchor: at(9))])
    }

    @Test func feedDueCanCountFromTheEnd() {
        var settings = on
        settings.basis = .end
        let last = LastFeed(start: at(9), end: at(9.5), kind: .breast)
        #expect(planner.plan(settings: settings, lastFeed: last, active: nil, now: at(10)).first?.fireDate == at(12.5))
        // A bottle without a duration ends when it starts.
        let bottle = LastFeed(start: at(9), end: nil, kind: .bottle)
        #expect(planner.plan(settings: settings, lastFeed: bottle, active: nil, now: at(10)).first?.fireDate == at(12))
    }

    @Test func nothingWhenOffOverdueOrNoHistory() {
        let last = LastFeed(start: at(9), end: at(9.5), kind: .breast)
        #expect(planner.plan(settings: ReminderSettings(isEnabled: false), lastFeed: last, active: nil, now: at(10)).isEmpty)
        #expect(planner.plan(settings: on, lastFeed: last, active: nil, now: at(12)).isEmpty)
        #expect(planner.plan(settings: on, lastFeed: nil, active: nil, now: at(10)).isEmpty)
    }

    @Test func quietHoursDeferUntilMorning() {
        var settings = on
        settings.quietHours = .overnight
        let last = LastFeed(start: at(21), end: at(21.5), kind: .breast)
        let plan = planner.plan(settings: settings, lastFeed: last, active: nil, now: at(21.5))
        #expect(plan.first?.fireDate == at(30))
        #expect(plan.first?.deferredByQuietHours == true)
    }

    @Test func runningFeedReplacesFeedDueWithStillFeeding() {
        let active = SessionSnapshot(status: .active, segments: [
            Segment(side: .left, start: at(10), end: at(10.2)),
            Segment(side: .right, start: at(10.2)),
        ], startedAt: at(10))
        let last = LastFeed(start: at(7), end: at(7.5), kind: .breast)
        let plan = planner.plan(settings: on, lastFeed: last, active: active, now: at(10.3))
        #expect(plan.count == 1)
        #expect(plan.first?.kind == .stillFeeding)
        #expect(plan.first?.side == .right)
        #expect(plan.first?.fireDate == at(10.2).addingTimeInterval(45 * 60))
    }

    @Test func stillFeedingAsksOnlyOnThePhoneThatStartedTheFeed() {
        let active = SessionSnapshot(status: .active, segments: [Segment(side: .left, start: at(10))], startedAt: at(10))
        let last = LastFeed(start: at(7), end: at(7.5), kind: .breast)
        // The other parent's phone: no "Still feeding?", and no "feed due" while a feed runs.
        #expect(planner.plan(settings: on, lastFeed: last, active: active, activeStartedHere: false, now: at(10.3)).isEmpty)
    }

    @Test func stillFeedingIgnoresQuietHoursAndCountsPauses() {
        var settings = on
        settings.quietHours = .overnight
        settings.stillFeedingThreshold = 30 * 60
        let paused = SessionSnapshot(status: .paused, segments: [Segment(side: .left, start: at(2), end: at(2.25))], startedAt: at(2))
        let plan = planner.plan(settings: settings, lastFeed: nil, active: paused, now: at(2.3))
        #expect(plan == [PlannedReminder(kind: .stillFeeding, fireDate: at(2.75), anchor: at(2.25))])
    }

    @Test func stillFeedingRestartsAfterKeepGoing() {
        var active = SessionSnapshot(status: .active, segments: [Segment(side: .left, start: at(2))], startedAt: at(2))
        active.recoveryAcknowledgedAt = at(3)
        let plan = planner.plan(settings: on, lastFeed: nil, active: active, now: at(3.1))
        #expect(plan.first?.fireDate == at(3.75))
    }

    @Test func stillFeedingCanBeTurnedOff() {
        var settings = on
        settings.stillFeedingEnabled = false
        let active = SessionSnapshot(status: .active, segments: [Segment(side: .left, start: at(2))], startedAt: at(2))
        #expect(planner.plan(settings: settings, lastFeed: nil, active: active, now: at(2.1)).isEmpty)
    }

    @Test func lastFeedPicksTheNewerKind() {
        let breast = breastfeed(start: at(8), end: at(8.4))
        let bottle = BottleEntry(startedAt: at(9), contents: .formula, amountML: 90, durationSeconds: 600)
        #expect(LastFeed.latest(breast: breast, bottle: bottle) == LastFeed(start: at(9), end: at(9).addingTimeInterval(600), kind: .bottle))
        #expect(LastFeed.latest(breast: breast, bottle: nil) == LastFeed(start: at(8), end: at(8.4), kind: .breast))
        #expect(LastFeed.latest(breast: nil, bottle: nil) == nil)
    }

    /// The bug from a parent's Lock Screen: a breastfeed at 5:22 PM, then a 2 oz bottle at
    /// 8:11 PM. The reminder must move to 3 h after the bottle, not fire at 8:22 PM.
    @Test func aLaterBottleMovesTheReminderPastTheEarlierBreastfeed() {
        let breast = breastfeed(start: at(17 + 22.0 / 60), end: at(17.75))
        let bottle = BottleEntry(startedAt: at(20 + 11.0 / 60), contents: .formula, amountML: 59)
        let last = LastFeed.latest(breast: breast, bottle: bottle)
        #expect(last?.kind == .bottle)
        let plan = planner.plan(settings: on, lastFeed: last, active: nil, now: at(20.2))
        #expect(plan == [PlannedReminder(kind: .feedDue, fireDate: at(23 + 11.0 / 60), anchor: at(20 + 11.0 / 60))])
    }

    @Test func identifiersMapBackToTheirKind() {
        for kind in PlannedReminder.Kind.allCases {
            #expect(PlannedReminder.kind(forIdentifier: PlannedReminder.identifier(for: kind)) == kind)
        }
        #expect(PlannedReminder.kind(forIdentifier: "newbee.nightShift.summary") == nil)
    }
}

@Suite("Delivered reminders")
struct DeliveredReminderTests {
    @Test func feedDueIsOutdatedOnceANewerFeedStarted() {
        let anchor = at(17)
        // The bottle was logged after the reminder fired, with its time set back to 8:11 PM.
        let bottle = LastFeed(start: at(20), end: nil, kind: .bottle)
        #expect(ReminderPlanner.deliveredReminderIsOutdated(.feedDue, anchor: anchor, lastFeed: bottle, active: nil))
    }

    @Test func feedDueStaysForTheFeedItCountedFrom() {
        // Counting from the start: the same feed is still the last one.
        let same = LastFeed(start: at(17), end: at(17.5), kind: .breast)
        #expect(!ReminderPlanner.deliveredReminderIsOutdated(.feedDue, anchor: at(17), lastFeed: same, active: nil))
        // Counting from the end: the anchor is after that feed's start.
        #expect(!ReminderPlanner.deliveredReminderIsOutdated(.feedDue, anchor: at(17.5), lastFeed: same, active: nil))
        // No feeds at all (everything was deleted): nothing to compare with.
        #expect(!ReminderPlanner.deliveredReminderIsOutdated(.feedDue, anchor: at(17), lastFeed: nil, active: nil))
    }

    @Test func feedDueIsOutdatedOnceABreastfeedIsRunning() {
        let last = LastFeed(start: at(17), end: at(17.5), kind: .breast)
        let running = SessionSnapshot(status: .active, segments: [Segment(side: .left, start: at(20))], startedAt: at(20))
        #expect(ReminderPlanner.deliveredReminderIsOutdated(.feedDue, anchor: at(17), lastFeed: last, active: running))
    }

    @Test func stillFeedingIsOutdatedOnceNoFeedIsRunning() {
        let running = SessionSnapshot(status: .active, segments: [Segment(side: .left, start: at(2))], startedAt: at(2))
        let paused = SessionSnapshot(status: .paused, segments: [Segment(side: .left, start: at(2), end: at(2.5))], startedAt: at(2))
        #expect(!ReminderPlanner.deliveredReminderIsOutdated(.stillFeeding, anchor: at(2), lastFeed: nil, active: running))
        #expect(!ReminderPlanner.deliveredReminderIsOutdated(.stillFeeding, anchor: at(2.5), lastFeed: nil, active: paused))
        let ended = LastFeed(start: at(2), end: at(3), kind: .breast)
        #expect(ReminderPlanner.deliveredReminderIsOutdated(.stillFeeding, anchor: at(2), lastFeed: ended, active: nil))
    }
}
