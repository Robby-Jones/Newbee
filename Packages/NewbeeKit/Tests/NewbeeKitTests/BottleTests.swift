import Foundation
import Testing
@testable import NewbeeKit

@Suite("Bottle amounts")
struct BottleAmountTests {
    @Test func ouncesConvertToMillilitres() {
        #expect(approx(BottleAmount(2, .fluidOunces).milliliters, 59.147059125))
        #expect(BottleAmount(90, .milliliters).milliliters == 90)
    }

    @Test func conversionRoundsToDisplayPrecision() {
        #expect(BottleAmount(90, .milliliters).converted(to: .fluidOunces) == BottleAmount(3, .fluidOunces))
        #expect(BottleAmount(3, .fluidOunces).converted(to: .milliliters) == BottleAmount(89, .milliliters))
        #expect(BottleAmount(120, .milliliters).converted(to: .fluidOunces) == BottleAmount(4.1, .fluidOunces))
    }

    @Test func formatting() {
        #expect(BottleAmount(90, .milliliters).formatted == "90 mL")
        #expect(BottleAmount(2.5, .fluidOunces).formatted == "2.5 oz")
        #expect(BottleAmount(3, .fluidOunces).formatted == "3 oz")
        #expect(BottleAmount(89.6, .milliliters).formattedValue == "90")
    }

    @Test func parsing() {
        #expect(BottleAmount.parse("90", unit: .milliliters) == BottleAmount(90, .milliliters))
        #expect(BottleAmount.parse(" 2,5 ", unit: .fluidOunces) == BottleAmount(2.5, .fluidOunces))
        #expect(BottleAmount.parse("", unit: .milliliters) == nil)
        #expect(BottleAmount.parse("abc", unit: .milliliters) == nil)
        #expect(BottleAmount.parse("-5", unit: .milliliters) == nil)
    }

    @Test func stepperSnapsAndClamps() {
        #expect(BottleAmount(90, .milliliters).stepped(by: 1) == BottleAmount(100, .milliliters))
        #expect(BottleAmount(95, .milliliters).stepped(by: 1) == BottleAmount(100, .milliliters))
        #expect(BottleAmount(95, .milliliters).stepped(by: -1) == BottleAmount(90, .milliliters))
        #expect(BottleAmount(94, .milliliters).stepped(by: -1) == BottleAmount(90, .milliliters))
        #expect(BottleAmount(0, .milliliters).stepped(by: -1) == BottleAmount(0, .milliliters))
        #expect(BottleAmount(500, .milliliters).stepped(by: 1) == BottleAmount(500, .milliliters))
        #expect(BottleAmount(2, .fluidOunces).stepped(by: 1) == BottleAmount(2.5, .fluidOunces))
        // 500 mL is 16.9 oz: the stepper stops below the limit, never above it.
        #expect(BottleAmount(16.5, .fluidOunces).stepped(by: 1) == BottleAmount(16.9, .fluidOunces))
        #expect(BottleAmount(16.9, .fluidOunces).stepped(by: 1).milliliters <= 500)
    }

    @Test func presetsDefaultPerUnitAndRespectStoredValues() {
        #expect(BottlePresets.defaults(for: .milliliters).map(\.value) == [60, 90, 120])
        #expect(BottlePresets.defaults(for: .fluidOunces).map(\.value) == [2, 3, 4])
        #expect(BottlePresets.amounts(storedML: nil, unit: .milliliters) == BottlePresets.defaults(for: .milliliters))
        #expect(BottlePresets.amounts(storedML: [120, 0, 60, 900, 60], unit: .milliliters).map(\.value) == [60, 120])
        #expect(BottlePresets.amounts(storedML: [90], unit: .fluidOunces) == [BottleAmount(3, .fluidOunces)])
    }
}

@Suite("Bottle validation")
struct BottleRulesTests {
    let rules = BottleRules()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func draft(_ ml: Double, startedAt: Date? = nil, duration: TimeInterval? = nil) -> BottleDraft {
        BottleDraft(contents: .formula, amount: BottleAmount(ml, .milliliters), startedAt: startedAt ?? now, durationSeconds: duration)
    }

    @Test func acceptsAValidDraft() throws {
        var d = draft(90, startedAt: now.addingTimeInterval(-600), duration: 300)
        d.notes = "  sleepy  "
        let entry = try rules.entry(from: d, now: now)
        #expect(entry.amountML == 90)
        #expect(entry.contents == .formula)
        #expect(entry.endedAt == now.addingTimeInterval(-300))
        #expect(entry.notes == "sleepy")
    }

    @Test func amountMustBePositiveAndAtMost500mL() {
        #expect(rules.problems(with: draft(0), now: now) == [.amountNotPositive])
        #expect(rules.problems(with: draft(.nan), now: now) == [.amountNotPositive])
        #expect(rules.problems(with: draft(500), now: now).isEmpty)
        #expect(rules.problems(with: draft(501), now: now) == [.amountTooLarge(maximumML: 500)])
        // 16.9 oz rounds to under 500 mL; 17 oz is over.
        let oz = BottleDraft(contents: .breastMilk, amount: BottleAmount(17, .fluidOunces), startedAt: now)
        #expect(rules.problems(with: oz, now: now) == [.amountTooLarge(maximumML: 500)])
    }

    @Test func timeCannotBeInTheFuture() {
        #expect(rules.problems(with: draft(90, startedAt: now.addingTimeInterval(30)), now: now).isEmpty)
        #expect(rules.problems(with: draft(90, startedAt: now.addingTimeInterval(3600)), now: now) == [.startInFuture])
        #expect(rules.problems(with: draft(90, startedAt: now, duration: 600), now: now) == [.endInFuture])
    }

    @Test func durationMustBeSensible() {
        let past = now.addingTimeInterval(-4 * 3600)
        #expect(rules.problems(with: draft(90, startedAt: past, duration: 0), now: now) == [.durationNotPositive])
        #expect(rules.problems(with: draft(90, startedAt: past, duration: 3 * 3600), now: now) == [.durationTooLong(maximumSeconds: 7200)])
    }

    @Test func throwsTheFirstProblem() {
        #expect(throws: BottleValidationError.amountNotPositive) {
            try rules.entry(from: draft(0, startedAt: now.addingTimeInterval(3600)), now: now)
        }
    }
}

@MainActor
@Suite("Bottle log")
struct BottleLogTests {
    let clock = TestClock()
    let repository = InMemoryBottleRepository()
    var log: BottleLog { BottleLog(repository: repository, clock: clock) }

    @Test func firstDraftIsBreastMilkAtTheMiddlePresetNow() {
        let draft = log.newDraft(unit: .milliliters)
        #expect(draft.contents == .breastMilk)
        #expect(draft.amount == BottleAmount(90, .milliliters))
        #expect(draft.startedAt == clock.now)
        #expect(!draft.isEditing)
        #expect(log.newDraft(unit: .fluidOunces).amount == BottleAmount(3, .fluidOunces))
    }

    @Test func nextDraftRepeatsTheLastBottle() throws {
        try log.save(BottleDraft(contents: .formula, amount: BottleAmount(4, .fluidOunces), startedAt: clock.now))
        clock.advance(by: 3 * 3600)
        let draft = log.newDraft(unit: .fluidOunces)
        #expect(draft.contents == .formula)
        #expect(draft.amount == BottleAmount(4, .fluidOunces))
        #expect(draft.startedAt == clock.now)
        #expect(log.newDraft(unit: .milliliters).amount == BottleAmount(118, .milliliters))
    }

    @Test func draftCanStartEarlierButNotLater() {
        let earlier = clock.now.addingTimeInterval(-3 * 86_400)
        #expect(log.newDraft(unit: .milliliters, at: earlier).startedAt == earlier)
        #expect(log.newDraft(unit: .milliliters, at: clock.now.addingTimeInterval(3600)).startedAt == clock.now)
    }

    @Test func saveStoresCanonicalMillilitresAndTheEnteredUnit() throws {
        let result = try log.save(BottleDraft(contents: .breastMilk, amount: BottleAmount(2, .fluidOunces), startedAt: clock.now))
        #expect(result.previous == nil)
        let stored = try #require(repository.entries[result.saved.id])
        #expect(approx(stored.amountML, 59.147059125))
        #expect(stored.enteredUnit == .fluidOunces)
        #expect(stored.enteredAmount == BottleAmount(2, .fluidOunces))
    }

    @Test func invalidDraftIsNotSaved() {
        #expect(throws: BottleValidationError.amountNotPositive) {
            try log.save(BottleDraft(contents: .formula, amount: BottleAmount(0, .milliliters), startedAt: clock.now))
        }
        #expect(repository.entries.isEmpty)
    }

    @Test func editReplacesInPlaceAndUndoRestoresTheOriginal() throws {
        let created = try log.save(BottleDraft(contents: .formula, amount: BottleAmount(90, .milliliters), startedAt: clock.now)).saved
        clock.advance(by: 60)
        var draft = try #require(try log.editDraft(id: created.id))
        #expect(draft.isEditing)
        draft.amount = BottleAmount(120, .milliliters)
        draft.contents = .breastMilk
        let edit = try log.save(draft)
        #expect(edit.previous == created)
        #expect(repository.entries.count == 1)
        #expect(repository.entries[created.id]?.amountML == 120)

        try log.undo(edit)
        #expect(repository.entries[created.id] == created)
    }

    @Test func undoOfANewEntryDeletesIt() throws {
        let result = try log.save(BottleDraft(contents: .formula, amount: BottleAmount(90, .milliliters), startedAt: clock.now))
        try log.undo(result)
        #expect(repository.entries.isEmpty)
    }

    @Test func deleteReturnsTheEntrySoItCanBeRestored() throws {
        let entry = try log.save(BottleDraft(contents: .other, amount: BottleAmount(30, .milliliters), startedAt: clock.now)).saved
        let deleted = try log.delete(id: entry.id)
        #expect(deleted == entry)
        #expect(repository.entries.isEmpty)
        #expect(try log.delete(id: entry.id) == nil)
        try log.restore(entry)
        #expect(repository.entries[entry.id] == entry)
    }

    @Test func storageFailureSurfaces() {
        repository.simulatedFailure = DiskFull()
        #expect(throws: DiskFull.self) {
            try log.save(BottleDraft(contents: .formula, amount: BottleAmount(90, .milliliters), startedAt: clock.now))
        }
    }

    @Test func recentIsNewestFirst() throws {
        let first = try log.save(BottleDraft(contents: .formula, amount: BottleAmount(60, .milliliters), startedAt: clock.now)).saved
        clock.advance(by: 3600)
        let second = try log.save(BottleDraft(contents: .formula, amount: BottleAmount(90, .milliliters), startedAt: clock.now)).saved
        #expect(try log.recent(limit: 5).map(\.id) == [second.id, first.id])
        #expect(try log.recent(limit: 1).map(\.id) == [second.id])
    }

    @Test func daySummaryCountsBottlesThatStartedThatDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight = calendar.startOfDay(for: clock.now)
        let entries = [
            BottleEntry(startedAt: midnight.addingTimeInterval(-60), contents: .formula, amountML: 500),
            BottleEntry(startedAt: midnight, contents: .formula, amountML: 90),
            BottleEntry(startedAt: midnight.addingTimeInterval(3600), contents: .breastMilk, amountML: 60),
            BottleEntry(startedAt: midnight.addingTimeInterval(7200), contents: .formula, amountML: 30),
            BottleEntry(startedAt: midnight.addingTimeInterval(86_400), contents: .formula, amountML: 500),
        ]
        for entry in entries { try repository.save(entry, modifiedAt: clock.now) }

        let summary = try log.summary(forDayContaining: midnight.addingTimeInterval(5000), calendar: calendar)
        #expect(summary.count == 3)
        #expect(summary.totalML == 180)
        #expect(summary.mlByContents == [.formula: 120, .breastMilk: 60])
        #expect(try log.summary(forDayContaining: midnight.addingTimeInterval(2 * 86_400), calendar: calendar).isEmpty)
    }
}
