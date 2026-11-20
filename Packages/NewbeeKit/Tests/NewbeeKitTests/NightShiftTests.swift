import Foundation
import Testing
@testable import NewbeeKit

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-11-07 00:00 UTC. Hours past 24 are the next day.
private let midnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 7))!

private func at(_ hour: Double) -> Date { midnight.addingTimeInterval(hour * 3600) }

private let schedule = NightShiftSchedule()
private let me = "_me"
private let partner = "_partner"

/// A shift from 9 PM until 7 AM the next morning.
private func shift(onDuty: String = me) -> NightShift {
    NightShift.starting(for: onDuty, at: at(21), schedule: schedule, calendar: utc)
}

@Suite("Night shift")
struct NightShiftTests {
    @Test func aShiftRunsUntilTheNextMorningTime() {
        #expect(shift().endsAt == at(31))
        // Started after midnight, it ends the same morning.
        #expect(NightShift.starting(for: me, at: at(26), schedule: schedule, calendar: utc).endsAt == at(31))
        let late = NightShiftSchedule(morningMinute: 8 * 60 + 30)
        #expect(NightShift.starting(for: me, at: at(21), schedule: late, calendar: utc).endsAt == at(32.5))
    }

    @Test func eachParentSeesTheirOwnSideOfIt() {
        let night = shift()
        #expect(night.duty(for: me, at: at(23)) == .onDuty(until: at(31)))
        #expect(night.duty(for: partner, at: at(23)) == .offDuty(until: at(31)))
        #expect(night.duty(for: me, at: at(31)) == .none)
        #expect(night.duty(for: partner, at: at(33)) == .none)
    }

    @Test func endingEarlyAndTakingOver() {
        let ended = shift().ended(at: at(29))
        #expect(ended.end == at(29))
        #expect(ended.duty(for: me, at: at(29.5)) == .none)
        #expect(ended.changedAt == at(29))

        let taken = shift().takenOver(by: partner, at: at(26))
        #expect(taken.onDuty == partner)
        #expect(taken.startedAt == at(26))
        #expect(taken.endsAt == at(31))
        #expect(taken.duty(for: me, at: at(27)) == .offDuty(until: at(31)))
    }

    @Test func itTravelsAsOneRecord() throws {
        let night = shift().ended(at: at(29))
        #expect(night.key == SyncKey(kind: .nightShift, id: "current"))
        let content = night.content()
        #expect(NightShift.decode(content) == night)
        #expect(SyncCodec.fingerprint(of: content, kind: .nightShift) == night.fingerprint())
        #expect(night.fingerprint() != shift().fingerprint())
    }
}

@Suite("Night shift card on Home")
struct NightShiftCardTests {
    private func card(_ shift: NightShift?, me id: String? = me, at hour: Double, dismissed: Date? = nil) -> NightShiftCard? {
        NightShiftCard.current(shift: shift, me: id, now: at(hour), dismissedShiftStart: dismissed)
    }

    @Test func theOfferIsThereWheneverNobodyIsOnCall() {
        #expect(card(nil, at: 12) == .offerStart)
        #expect(card(nil, at: 20) == .offerStart)
        // The offer doesn't need to know who this parent is; tapping it finds out.
        #expect(card(nil, me: nil, at: 20) == .offerStart)
    }

    @Test func whoeverIsOnDutyIsShownOnBothPhones() {
        #expect(card(shift(), at: 23) == .onDuty(until: at(31)))
        #expect(card(shift(onDuty: partner), at: 23) == .partnerOnDuty(until: at(31)))
        // Not knowing who this parent is, the phone can't say whose shift it is.
        #expect(card(shift(), me: nil, at: 23) == nil)
    }

    @Test func theParentWhoSleptGetsTheSummaryUntilTheyDismissIt() {
        let theirs = shift(onDuty: partner)
        #expect(card(theirs, at: 31) == .summary(theirs))
        #expect(card(theirs, at: 40) == .summary(theirs))
        #expect(card(theirs, at: 31, dismissed: theirs.startedAt) == .offerStart)
        // Twelve hours on it has gone by itself, and the offer is back.
        #expect(card(theirs, at: 43.5) == .offerStart)
    }

    @Test func theParentWhoWasOnDutyGetsNoSummary() {
        #expect(card(shift(), at: 31) == .offerStart)
        #expect(card(shift(), at: 44) == .offerStart)
    }

    @Test func aShiftEndedEarlyShowsItsSummaryRightAway() {
        let ended = shift(onDuty: partner).ended(at: at(29))
        #expect(card(ended, at: 29.5) == .summary(ended))
        // Once dismissed, either parent can start a new shift.
        #expect(card(ended, at: 29.5, dismissed: ended.startedAt) == .offerStart)
    }
}

@Suite("Night summary")
struct NightSummaryTests {
    private func breastfeed(_ hour: Double, minutes: Double) -> FeedEntry {
        FeedEntry(
            id: UUID(), start: at(hour), end: at(hour).addingTimeInterval(minutes * 60),
            details: .breast(left: minutes * 30, right: minutes * 30, firstSide: .left, lastSide: .right)
        )
    }

    private func bottle(_ hour: Double, ml: Double) -> FeedEntry {
        FeedEntry(id: UUID(), start: at(hour), end: nil, details: .bottle(BottleSummary(contents: .formula, amountML: ml)))
    }

    @Test func countsOnlyFeedsThatStartedDuringTheShift() {
        let feeds = [
            breastfeed(20.5, minutes: 15),  // before the shift
            breastfeed(22, minutes: 20),
            bottle(25.5, ml: 90),
            breastfeed(29, minutes: 10),
            bottle(31, ml: 120),            // at 7:00, after it
        ]
        let summary = NightSummary(shift: shift(onDuty: partner), feeds: feeds)
        #expect(summary.feeds == 3)
        #expect(summary.breastfeeds == 2)
        #expect(summary.nursing == 30 * 60)
        #expect(summary.bottles == 1)
        #expect(summary.bottleML == 90)
        #expect(summary.lastFeedStart == at(29))
        #expect(summary.start == at(21))
        #expect(summary.end == at(31))
    }

    @Test func aQuietNightIsEmpty() {
        let summary = NightSummary(shift: shift(onDuty: partner), feeds: [])
        #expect(summary.feeds == 0)
        #expect(summary.lastFeedStart == nil)
    }

    @Test func aShiftEndedEarlyStopsCountingThere() {
        let ended = shift(onDuty: partner).ended(at: at(26))
        let summary = NightSummary(shift: ended, feeds: [breastfeed(22, minutes: 20), breastfeed(29, minutes: 10)])
        #expect(summary.feeds == 1)
        #expect(summary.end == at(26))
    }
}

@Suite("Reminders during a night shift")
struct NightShiftReminderTests {
    private let planner = ReminderPlanner(calendar: utc)
    private let settings = ReminderSettings(isEnabled: true, interval: 3 * 3600, quietHours: .overnight)
    /// Fed at 11 PM, so the next reminder would be at 2 AM, in quiet hours.
    private let last = LastFeed(start: at(23), end: at(23.4), kind: .breast)

    @Test func withoutAShiftQuietHoursHoldTheReminder() {
        let plan = planner.plan(settings: settings, lastFeed: last, active: nil, now: at(23.5))
        #expect(plan.first?.fireDate == at(30))
        #expect(plan.first?.deferredByQuietHours == true)
        #expect(plan.first?.duringNightShift == false)
    }

    @Test func theParentOnDutyIsRemindedInQuietHours() {
        let plan = planner.plan(settings: settings, lastFeed: last, active: nil, duty: .onDuty(until: at(31)), now: at(23.5))
        #expect(plan.count == 1)
        #expect(plan.first?.fireDate == at(26))
        #expect(plan.first?.deferredByQuietHours == false)
        #expect(plan.first?.duringNightShift == true)
    }

    @Test func theOtherParentIsNotRemindedDuringTheShift() {
        #expect(planner.plan(settings: settings, lastFeed: last, active: nil, duty: .offDuty(until: at(31)), now: at(23.5)).isEmpty)
    }

    @Test func aReminderAfterTheShiftFollowsTheUsualRules() {
        // Fed at 5 AM: the reminder is due at 8 AM, after the shift and after quiet hours.
        let early = LastFeed(start: at(29), end: at(29.3), kind: .breast)
        for duty in [NightDuty.onDuty(until: at(31)), .offDuty(until: at(31))] {
            let plan = planner.plan(settings: settings, lastFeed: early, active: nil, duty: duty, now: at(29.5))
            #expect(plan.first?.fireDate == at(32))
            #expect(plan.first?.duringNightShift == false)
        }
    }

    @Test func remindersTurnedOffStayOffOnDuty() {
        let off = ReminderSettings(isEnabled: false)
        #expect(planner.plan(settings: off, lastFeed: last, active: nil, duty: .onDuty(until: at(31)), now: at(23.5)).isEmpty)
    }

    @Test func anOverdueReminderIsNotSentLateOnDuty() {
        #expect(planner.plan(settings: settings, lastFeed: last, active: nil, duty: .onDuty(until: at(31)), now: at(26.5)).isEmpty)
    }
}

@MainActor
@Suite("Night shift between phones")
struct NightShiftSyncTests {
    @Test func theShiftReachesTheOtherParentAndTheLaterChangeWins() throws {
        let zone = FakeCloudZone()
        let clock = TestClock(wall: at(21))
        let mine = FakeDevice(zone: zone, clock: clock)
        let theirs = FakeDevice(zone: zone, clock: clock)

        mine.store.shift = shift()
        try syncUntilQuiet(mine, theirs)
        #expect(theirs.store.shift == shift())

        // The other parent takes over at 2 AM; the first one's phone follows.
        clock.advance(by: 5 * 3600)
        theirs.store.shift = shift().takenOver(by: partner, at: at(26))
        try syncUntilQuiet(mine, theirs)
        #expect(mine.store.shift?.onDuty == partner)

        // Both change it while offline: the later change is the one both end up with.
        clock.advance(by: 3600)
        mine.store.shift = mine.store.shift?.takenOver(by: me, at: at(27))
        try mine.core.scan()
        clock.advance(by: 3600)
        theirs.store.shift = theirs.store.shift?.ended(at: at(28))
        try theirs.core.scan()
        try syncUntilQuiet(mine, theirs)
        #expect(mine.store.shift == theirs.store.shift)
        #expect(mine.store.shift?.endedAt == at(28))
    }
}
