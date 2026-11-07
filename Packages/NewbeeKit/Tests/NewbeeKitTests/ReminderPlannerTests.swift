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
}
