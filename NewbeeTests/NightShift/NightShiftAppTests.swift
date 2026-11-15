import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// Records what the scheduler asks AlarmKit to do.
actor FakeNightAlarmClient: NightAlarmClient {
    nonisolated let isSupported = true
    var allowed: Bool
    private(set) var alarm: ScheduledNotification?
    private(set) var requestCount = 0

    init(allowed: Bool = true) {
        self.allowed = allowed
    }

    func requestPermission() async -> Bool {
        requestCount += 1
        return allowed
    }

    func replace(with alarm: ScheduledNotification?) async -> Bool {
        self.alarm = allowed ? alarm : nil
        return self.alarm != nil
    }
}

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "NewbeeTests.NightShift.\(UUID().uuidString)")!
}

@MainActor
@Suite("Night shift store")
struct NightShiftStoreTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func shift(onDuty: String = "_me") -> NightShift {
        NightShift(onDuty: onDuty, startedAt: now, endsAt: now.addingTimeInterval(10 * 3_600), changedAt: now)
    }

    @Test func theShiftSurvivesARelaunch() {
        let defaults = freshDefaults()
        let store = NightShiftStore(defaults: defaults)
        #expect(store.shift == nil)
        store.setMe("_me")
        store.set(shift())
        store.dismissSummary(of: shift())

        let relaunched = NightShiftStore(defaults: defaults)
        #expect(relaunched.shift == shift())
        #expect(relaunched.me == "_me")
        #expect(relaunched.dismissedSummaryStart == now)

        relaunched.set(nil)
        #expect(NightShiftStore(defaults: defaults).shift == nil)
    }

    /// A change made here needs to sync; one that arrived through sync must not be sent back.
    @Test func onlyLocalChangesAskToSync() {
        let store = NightShiftStore(defaults: freshDefaults())
        var changes = 0, localChanges = 0
        store.onChange = { changes += 1 }
        store.onLocalChange = { localChanges += 1 }

        store.set(shift())
        #expect((changes, localChanges) == (1, 1))
        store.applyFromSync(shift(onDuty: "_partner"))
        #expect((changes, localChanges) == (2, 1))
        // The same value again changes nothing.
        store.applyFromSync(shift(onDuty: "_partner"))
        store.set(shift(onDuty: "_partner"))
        #expect((changes, localChanges) == (2, 1))
    }

    @Test func theShiftCrossesToTheOtherPhone() throws {
        let clock = TestClock()
        let mine = NightShiftStore(defaults: freshDefaults())
        let theirs = NightShiftStore(defaults: freshDefaults())
        let myCore = SyncCore(store: SwiftDataSyncStore(container: try makeInMemoryContainer(), nightShift: mine), clock: clock)
        let theirCore = SyncCore(store: SwiftDataSyncStore(container: try makeInMemoryContainer(), nightShift: theirs), clock: clock)

        mine.set(shift())
        let pending = try myCore.scan()
        #expect(pending.saves == [shift().key])
        let record = try #require(try myCore.outgoingRecord(for: shift().key))
        #expect(try theirCore.receive(modifications: [record]))
        #expect(theirs.shift == shift())
        // What arrived matches what was sent, so it isn't sent back.
        #expect(try theirCore.scan().saves.isEmpty)

        #expect(try theirCore.receive(modifications: [], deletions: [shift().key]))
        #expect(theirs.shift == nil)
    }
}

@MainActor
@Suite("Night shift reminders")
struct NightShiftReminderSchedulingTests {
    let clock = TestClock()
    let notifications = FakeNotificationClient()
    let alarms = FakeNightAlarmClient()

    var feedDueID: String { PlannedReminder.identifier(for: .feedDue) }

    /// Reminders on with quiet hours around the clock, a bottle just logged, and a partner.
    private func makeDependencies() throws -> AppDependencies {
        let dependencies = AppDependencies(
            clock: clock, storage: .inMemory, notifications: notifications, alarms: alarms, defaults: freshDefaults()
        )
        dependencies.preferences.reminders.isEnabled = true
        dependencies.preferences.reminders.quietHours = QuietHours(startMinute: 0, endMinute: 1_439)
        dependencies.nightShift.hasPartnerOverride = true
        dependencies.nightShift.store.setMe("_me")
        try dependencies.bottleLog.save(dependencies.bottleLog.newDraft(unit: .milliliters))
        return dependencies
    }

    private func shift(onDuty: String) -> NightShift {
        NightShift(onDuty: onDuty, startedAt: clock.now, endsAt: clock.now.addingTimeInterval(10 * 3_600), changedAt: clock.now)
    }

    @Test func quietHoursHoldTheReminderUntilSomeoneIsOnDuty() async throws {
        let dependencies = try makeDependencies()
        let due = clock.now.addingTimeInterval(3 * 3_600)
        await dependencies.reminders.reschedule()
        #expect(await notifications.pending[feedDueID]?.fireDate != due)

        dependencies.nightShift.store.set(shift(onDuty: "_me"))
        await dependencies.reminders.reschedule()
        #expect(await notifications.pending[feedDueID]?.fireDate == due)
        #expect(await notifications.pending[ReminderScheduler.nightSummaryIdentifier] == nil)
        #expect(dependencies.nightShift.duty(at: clock.now) == .onDuty(until: clock.now.addingTimeInterval(10 * 3_600)))
    }

    @Test func theSleepingParentGetsOnlyTheSummary() async throws {
        let dependencies = try makeDependencies()
        dependencies.nightShift.store.set(shift(onDuty: "_partner"))
        await dependencies.reminders.reschedule()

        #expect(await notifications.pending[feedDueID] == nil)
        let summary = try #require(await notifications.pending[ReminderScheduler.nightSummaryIdentifier])
        #expect(summary.fireDate == clock.now.addingTimeInterval(10 * 3_600))
        #expect(summary.title == "While you slept")
        // The bottle logged at the start of the shift is the night so far.
        #expect(summary.body.hasPrefix("1 feed, at "))
    }

    @Test func endingTheShiftPutsBothPhonesBackToNormal() async throws {
        let dependencies = try makeDependencies()
        let due = clock.now.addingTimeInterval(3 * 3_600)
        dependencies.nightShift.store.set(shift(onDuty: "_me"))
        clock.advance(by: 60)
        dependencies.nightShift.endShift()
        await dependencies.reminders.reschedule()

        #expect(dependencies.nightShift.store.shift?.endedAt == clock.now)
        #expect(dependencies.nightShift.duty(at: clock.now) == .none)
        // Quiet hours hold the reminder again.
        let pending = try #require(await notifications.pending[feedDueID])
        #expect(pending.fireDate != due)
    }

    @Test func withoutAPartnerAShiftChangesNothing() async throws {
        let dependencies = try makeDependencies()
        dependencies.nightShift.hasPartnerOverride = false
        dependencies.nightShift.store.set(shift(onDuty: "_partner"))
        await dependencies.reminders.reschedule()
        #expect(await notifications.pending[feedDueID] != nil)
        #expect(await notifications.pending[ReminderScheduler.nightSummaryIdentifier] == nil)
        #expect(dependencies.nightShift.card(at: clock.now) == nil)
    }

    @Test func ringAsAlarmReplacesTheNotificationWhileOnDuty() async throws {
        let dependencies = try makeDependencies()
        #expect(await dependencies.nightShift.setAlarm(true))
        dependencies.nightShift.store.set(shift(onDuty: "_me"))
        await dependencies.reminders.reschedule()

        #expect(await alarms.alarm?.fireDate == clock.now.addingTimeInterval(3 * 3_600))
        #expect(await alarms.alarm?.title == "Feeding reminder")
        #expect(await notifications.pending[feedDueID] == nil)

        // Off duty again: the alarm is gone and the reminder is a notification as before.
        dependencies.nightShift.endShift()
        await dependencies.reminders.reschedule()
        #expect(await alarms.alarm == nil)
        #expect(await notifications.pending[feedDueID] != nil)
    }

    @Test func anAlarmThatIsNotAllowedStaysANotification() async throws {
        let denied = FakeNightAlarmClient(allowed: false)
        let dependencies = AppDependencies(
            clock: clock, storage: .inMemory, notifications: notifications, alarms: denied, defaults: freshDefaults()
        )
        dependencies.preferences.reminders.isEnabled = true
        dependencies.nightShift.hasPartnerOverride = true
        dependencies.nightShift.store.setMe("_me")
        try dependencies.bottleLog.save(dependencies.bottleLog.newDraft(unit: .milliliters))

        #expect(await dependencies.nightShift.setAlarm(true) == false)
        #expect(dependencies.preferences.nightShiftAlarm == false)
        dependencies.nightShift.store.set(shift(onDuty: "_me"))
        await dependencies.reminders.reschedule()
        #expect(await notifications.pending[feedDueID] != nil)
    }

    @Test func goingOnDutyStartsAShiftOrTakesOneOver() async throws {
        let dependencies = try makeDependencies()
        await dependencies.nightShift.goOnDuty()
        let started = try #require(dependencies.nightShift.store.shift)
        #expect(started.onDuty == "_me")
        #expect(started.startedAt == clock.now)
        #expect(started.endsAt > clock.now)

        // The partner's shift, taken over: same morning, this parent on duty from now.
        let theirs = shift(onDuty: "_partner")
        dependencies.nightShift.store.applyFromSync(theirs)
        clock.advance(by: 3_600)
        await dependencies.nightShift.goOnDuty()
        #expect(dependencies.nightShift.store.shift?.onDuty == "_me")
        #expect(dependencies.nightShift.store.shift?.startedAt == clock.now)
        #expect(dependencies.nightShift.store.shift?.endsAt == theirs.endsAt)
    }

    @Test func deleteAllDataEndsTheShiftToo() async throws {
        let dependencies = try makeDependencies()
        dependencies.nightShift.store.set(shift(onDuty: "_me"))
        try await dependencies.deleteAllData()
        #expect(dependencies.nightShift.store.shift == nil)
    }
}

@MainActor
@Suite("Night shift wording")
struct NightShiftWordingTests {
    private let shift = NightShift(
        onDuty: "_partner",
        startedAt: Date(timeIntervalSince1970: 1_800_000_000),
        endsAt: Date(timeIntervalSince1970: 1_800_036_000),
        changedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    @Test func aQuietNightSaysSo() {
        let summary = NightSummary(shift: shift, feeds: [])
        #expect(NightShiftCardView.summaryHeadline(summary) == "No feeds were logged.")
        #expect(NightShiftCardView.summaryDetail(summary, unit: .fluidOunces) == nil)
        let notification = ReminderScheduler.summaryNotification(summary, at: shift.end)
        #expect(notification.body == "Your partner's shift has ended. Open Newbee to see the night.")
        #expect(notification.fireDate == shift.end)
    }

    @Test func aBusyNightIsCountedByKind() {
        let start = shift.startedAt
        let feeds = [
            FeedEntry(id: UUID(), start: start.addingTimeInterval(3_600), end: nil, details: .breast(left: 600, right: 480, firstSide: .left, lastSide: .right)),
            FeedEntry(id: UUID(), start: start.addingTimeInterval(14_400), end: nil, details: .bottle(BottleSummary(contents: .formula, amountML: 90))),
        ]
        let summary = NightSummary(shift: shift, feeds: feeds)
        #expect(NightShiftCardView.summaryHeadline(summary).hasPrefix("2 feeds, the last at "))
        #expect(NightShiftCardView.summaryDetail(summary, unit: .milliliters) == "18 min nursing · 90 mL by bottle")
    }

    @Test func theCardSaysWhatWillRing() {
        let until = shift.endsAt
        #expect(NightShiftCardView.onDutySubtitle(until: until, remindersOn: true).hasSuffix("Feed reminders ring only on this iPhone."))
        #expect(NightShiftCardView.onDutySubtitle(until: until, remindersOn: false).hasSuffix("Feed reminders are off."))
        #expect(NightShiftCardView.offerSubtitle(until: until, remindersOn: true).hasPrefix("Feed reminders ring only on your iPhone until "))
    }
}
