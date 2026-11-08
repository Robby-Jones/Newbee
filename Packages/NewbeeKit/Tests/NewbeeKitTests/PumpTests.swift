import Foundation
import Testing
@testable import NewbeeKit

@Suite("Pump validation")
struct PumpRulesTests {
    let rules = PumpRules()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func draft(_ left: Double, _ right: Double, startedAt: Date? = nil, duration: TimeInterval? = nil) -> PumpDraft {
        PumpDraft(
            left: BottleAmount(left, .milliliters),
            right: BottleAmount(right, .milliliters),
            startedAt: startedAt ?? now.addingTimeInterval(-3600),
            durationSeconds: duration
        )
    }

    @Test func acceptsAValidDraft() throws {
        var d = draft(70, 50, startedAt: now.addingTimeInterval(-900), duration: 900)
        d.notes = "  evening  "
        let entry = try rules.entry(from: d, now: now)
        #expect(entry.leftML == 70)
        #expect(entry.rightML == 50)
        #expect(entry.totalML == 120)
        #expect(entry.endedAt == now)
        #expect(entry.notes == "evening")
    }

    @Test func oneSideMayBeEmptyButNotBoth() {
        #expect(rules.problems(with: draft(80, 0), now: now).isEmpty)
        #expect(rules.problems(with: draft(0, 80), now: now).isEmpty)
        #expect(rules.problems(with: draft(0, 0), now: now) == [.amountNotPositive])
        #expect(rules.problems(with: draft(.nan, 10), now: now) == [.amountNotPositive])
    }

    @Test func eachSideIsLimitedTo500mL() {
        #expect(rules.problems(with: draft(500, 500), now: now).isEmpty)
        #expect(rules.problems(with: draft(501, 10), now: now) == [.sideTooLarge(.left, maximumML: 500)])
        #expect(rules.problems(with: draft(10, 600), now: now) == [.sideTooLarge(.right, maximumML: 500)])
    }

    @Test func timesCannotBeInTheFuture() {
        #expect(rules.problems(with: draft(60, 60, startedAt: now.addingTimeInterval(3600)), now: now) == [.startInFuture])
        #expect(rules.problems(with: draft(60, 60, startedAt: now, duration: 600), now: now) == [.endInFuture])
    }

    @Test func durationMustBeSensible() {
        let past = now.addingTimeInterval(-4 * 3600)
        #expect(rules.problems(with: draft(60, 60, startedAt: past, duration: 0), now: now) == [.durationNotPositive])
        #expect(rules.problems(with: draft(60, 60, startedAt: past, duration: 3 * 3600), now: now) == [.durationTooLong(maximumSeconds: 7200)])
    }

    @Test func draftKeepsBothSidesInOneUnit() {
        var d = PumpDraft(left: BottleAmount(90, .milliliters), right: BottleAmount(2, .fluidOunces), startedAt: now)
        #expect(d.right == BottleAmount(59, .milliliters))
        #expect(d.total == BottleAmount(149, .milliliters))
        d.convert(to: .fluidOunces)
        #expect(d.left == BottleAmount(3, .fluidOunces))
        #expect(d.right == BottleAmount(2, .fluidOunces))
        d.setAmount(BottleAmount(0, .fluidOunces), on: .right)
        d.convert(to: .milliliters)
        #expect(d.right == BottleAmount(0, .milliliters))
    }
}

@MainActor
@Suite("Pump log")
struct PumpLogTests {
    let clock = TestClock()
    let repository = InMemoryPumpRepository()
    var log: PumpLog { PumpLog(repository: repository, clock: clock) }

    @Test func firstDraftEndsNowWithDefaultAmounts() {
        let draft = log.newDraft(unit: .milliliters)
        #expect(draft.left == BottleAmount(60, .milliliters))
        #expect(draft.right == BottleAmount(60, .milliliters))
        #expect(draft.durationSeconds == PumpLog.defaultDuration)
        #expect(draft.startedAt == clock.now.addingTimeInterval(-PumpLog.defaultDuration))
        #expect(log.problems(with: draft).isEmpty)
        #expect(log.newDraft(unit: .fluidOunces).left == BottleAmount(2, .fluidOunces))
    }

    @Test func nextDraftRepeatsTheLastSession() throws {
        try log.save(PumpDraft(
            left: BottleAmount(3, .fluidOunces),
            right: BottleAmount(2.5, .fluidOunces),
            startedAt: clock.now.addingTimeInterval(-1200),
            durationSeconds: 1200
        ))
        clock.advance(by: 3 * 3600)
        let draft = log.newDraft(unit: .fluidOunces)
        #expect(draft.left == BottleAmount(3, .fluidOunces))
        #expect(draft.right == BottleAmount(2.5, .fluidOunces))
        #expect(draft.durationSeconds == 1200)
        #expect(draft.startedAt == clock.now.addingTimeInterval(-1200))
    }

    @Test func editUndoRestoresThePreviousVersion() throws {
        let created = try log.save(log.newDraft(unit: .milliliters))
        var edit = try #require(try log.editDraft(id: created.saved.id))
        #expect(edit.isEditing)
        edit.setAmount(BottleAmount(100, .milliliters), on: .left)
        let edited = try log.save(edit)
        #expect(edited.previous == created.saved)
        #expect(repository.entries[created.saved.id]?.leftML == 100)
        try log.undo(edited)
        #expect(repository.entries[created.saved.id] == created.saved)
        try log.undo(created)
        #expect(repository.entries.isEmpty)
    }

    @Test func deleteReturnsTheEntryForUndo() throws {
        let created = try log.save(log.newDraft(unit: .milliliters))
        let deleted = try #require(try log.delete(id: created.saved.id))
        #expect(repository.entries.isEmpty)
        try log.restore(deleted)
        #expect(repository.entries[deleted.id] == deleted)
        #expect(try log.delete(id: UUID()) == nil)
    }

    @Test func daySummaryTotalsEachSide() throws {
        try log.save(log.newDraft(unit: .milliliters))
        var second = log.newDraft(unit: .milliliters)
        second.setAmount(BottleAmount(40, .milliliters), on: .right)
        try log.save(second)
        let summary = try log.summary(forDayContaining: clock.now)
        #expect(summary.count == 2)
        #expect(summary.leftML == 120)
        #expect(summary.rightML == 100)
        #expect(summary.totalML == 220)
        #expect(summary.duration == 2 * PumpLog.defaultDuration)
    }
}

@Suite("History with pumping")
struct HistoryTimelineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let day = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400))

    func feed(_ hours: Double) -> FeedEntry {
        FeedEntry(id: UUID(), start: day.addingTimeInterval(hours * 3600), end: nil, details: .bottle(BottleSummary(contents: .formula, amountML: 90)))
    }

    func pump(_ hours: Double) -> PumpEntry {
        PumpEntry(startedAt: day.addingTimeInterval(hours * 3600), leftML: 60, rightML: 60)
    }

    @Test func pumpsInterleaveWithoutChangingFeedGaps() {
        let feeds = [feed(1), feed(4)]
        let pumps = [pump(2), pump(-3)]
        let days = HistoryTimeline.days(feeds: feeds, pumps: pumps, calendar: calendar)
        #expect(days.count == 2)
        #expect(days[0].items.map(\.id) == [feeds[1].id, pumps[0].id, feeds[0].id])
        if case .feed(let row) = days[0].items[0] {
            #expect(approx(row.sincePrevious, 3 * 3600, tolerance: 1e-3))
        } else {
            Issue.record("Expected the newest item to be a feed")
        }
        #expect(days[1].items.map(\.id) == [pumps[1].id])
    }

    @Test func filtersPickFeedsOrPumps() {
        let feeds = [feed(1)]
        let pumps = [pump(2)]
        #expect(HistoryTimeline.days(feeds: feeds, pumps: pumps, filter: .pump, calendar: calendar).flatMap(\.items).map(\.id) == [pumps[0].id])
        #expect(HistoryTimeline.days(feeds: feeds, pumps: pumps, filter: .bottle, calendar: calendar).flatMap(\.items).map(\.id) == [feeds[0].id])
        #expect(HistoryTimeline.days(feeds: feeds, pumps: pumps, filter: .breast, calendar: calendar).isEmpty)
        #expect(!FeedFilter.pump.includes(feeds[0]))
    }
}
