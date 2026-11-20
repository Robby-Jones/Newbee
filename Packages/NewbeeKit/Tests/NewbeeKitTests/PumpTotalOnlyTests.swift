import Foundation
import Testing
@testable import NewbeeKit

/// Settings › "Log pumping as total only": one total instead of left and right, for new entries
/// only. Entries keep the way they were logged.
@MainActor
@Suite("Pumping total only")
struct PumpTotalOnlyTests {
    let clock = TestClock()
    let repository = InMemoryPumpRepository()
    var log: PumpLog { PumpLog(repository: repository, clock: clock) }
    let rules = PumpRules()

    @Test func aTotalIsStoredHalfOnEachSideAndMarked() throws {
        let draft = PumpDraft(total: BottleAmount(150, .milliliters), startedAt: clock.now.addingTimeInterval(-900), durationSeconds: 900)
        #expect(draft.isTotalOnly)
        #expect(draft.total == BottleAmount(150, .milliliters))
        let entry = try rules.entry(from: draft, now: clock.now)
        #expect(entry.isTotalOnly)
        #expect(entry.leftML == 75)
        #expect(entry.rightML == 75)
        #expect(entry.totalML == 150)
    }

    @Test func aTotalIsLimitedToBothSidesTogether() {
        let start = clock.now.addingTimeInterval(-3600)
        #expect(rules.problems(with: PumpDraft(total: BottleAmount(1000, .milliliters), startedAt: start), now: clock.now).isEmpty)
        #expect(rules.problems(with: PumpDraft(total: BottleAmount(1001, .milliliters), startedAt: start), now: clock.now)
            == [.totalTooLarge(maximumML: 1000)])
        #expect(rules.problems(with: PumpDraft(total: BottleAmount(0, .milliliters), startedAt: start), now: clock.now)
            == [.amountNotPositive])
    }

    @Test func firstTotalDraftUsesTheMiddleTotalPreset() {
        let draft = log.newDraft(unit: .milliliters, totalOnly: true)
        #expect(draft.isTotalOnly)
        #expect(draft.total == BottleAmount(120, .milliliters))
        #expect(log.newDraft(unit: .fluidOunces, totalOnly: true).total == BottleAmount(4, .fluidOunces))
        #expect(log.problems(with: draft).isEmpty)
    }

    @Test func totalDraftRepeatsTheLastSessionsTotal() throws {
        try log.save(PumpDraft(left: BottleAmount(70, .milliliters), right: BottleAmount(50, .milliliters),
                               startedAt: clock.now.addingTimeInterval(-600), durationSeconds: 600))
        let draft = log.newDraft(unit: .milliliters, totalOnly: true)
        #expect(draft.total == BottleAmount(120, .milliliters))
        #expect(draft.durationSeconds == 600)
    }

    @Test func editingKeepsTheWayAnEntryWasLogged() throws {
        let sided = try log.save(PumpDraft(left: BottleAmount(70, .milliliters), right: BottleAmount(50, .milliliters),
                                           startedAt: clock.now.addingTimeInterval(-600))).saved
        let total = try log.save(log.newDraft(unit: .milliliters, totalOnly: true)).saved

        let sidedEdit = try #require(try log.editDraft(id: sided.id, unit: .milliliters))
        #expect(!sidedEdit.isTotalOnly)
        #expect(sidedEdit.left == BottleAmount(70, .milliliters))

        var totalEdit = try #require(try log.editDraft(id: total.id, unit: .milliliters))
        #expect(totalEdit.isTotalOnly)
        #expect(totalEdit.total == BottleAmount(120, .milliliters))
        totalEdit.setTotal(BottleAmount(90, .milliliters))
        let saved = try log.save(totalEdit).saved
        #expect(saved.isTotalOnly)
        #expect(saved.totalML == 90)
        #expect(repository.entries[sided.id] == sided)
    }

    /// Opening a total-only entry in ounces and saving it unchanged keeps the exact milliliters.
    @Test func unchangedTotalKeepsItsMilliliters() throws {
        let saved = try log.save(PumpDraft(total: BottleAmount(125, .milliliters), startedAt: clock.now.addingTimeInterval(-600))).saved
        let edit = try #require(try log.editDraft(id: saved.id, unit: .fluidOunces))
        #expect(edit.unit == .fluidOunces)
        #expect(try log.save(edit).saved.totalML == 125)
    }

    @Test func unitSwitchConvertsTheTotal() {
        var draft = PumpDraft(total: BottleAmount(4, .fluidOunces), startedAt: clock.now)
        draft.convert(to: .milliliters)
        #expect(draft.total == BottleAmount(118, .milliliters))
        #expect(draft.isTotalOnly)
    }

    @Test func summariesLeaveTotalsOutOfTheSides() throws {
        let start = clock.now.addingTimeInterval(-600)
        let entries = [
            PumpEntry(startedAt: start, leftML: 70, rightML: 50),
            PumpEntry(startedAt: start, totalML: 100),
        ]
        let summary = PumpSummary(entries: entries)
        #expect(summary.count == 2)
        #expect(summary.leftML == 70)
        #expect(summary.rightML == 50)
        #expect(summary.totalML == 220)

        let report = FeedReport(feeds: [], pumps: entries, interval: DateInterval(start: start.addingTimeInterval(-3600), duration: 7200))
        #expect(report.pump.totalML == 220)
        #expect(report.pump.leftML == 70)
        #expect(report.pump.sidedCount == 1)
    }

    @Test func totalPresetsDoubleThePerSideDefaults() {
        #expect(PumpPresets.totalDefaults(for: .milliliters).map(\.value) == [60, 120, 180])
        #expect(PumpPresets.totalDefaults(for: .fluidOunces).map(\.value) == [2, 4, 6])
        #expect(PumpPresets.totalAmounts(storedML: [700, 90], unit: .milliliters).map(\.value) == [90, 700])
        #expect(PumpPresets.totalAmounts(storedML: [1200], unit: .milliliters) == PumpPresets.totalDefaults(for: .milliliters))
    }

    /// Entries with sides keep the exact payload bytes they synced with before total-only existed.
    @Test func syncPayloadOnlyCarriesTheMarkWhenSet() throws {
        let sided = FeedPayload.Pump(leftML: 60, rightML: 60, enteredUnit: "ml", durationSeconds: nil, totalOnly: false)
        #expect(sided.totalOnly == nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try #require(String(data: encoder.encode(sided), encoding: .utf8))
        #expect(!json.contains("totalOnly"))

        let total = FeedPayload.Pump(leftML: 60, rightML: 60, enteredUnit: "ml", durationSeconds: nil, totalOnly: true)
        let decoded = try JSONDecoder().decode(FeedPayload.Pump.self, from: encoder.encode(total))
        #expect(decoded.isTotalOnly)
        let old = try JSONDecoder().decode(FeedPayload.Pump.self, from: Data(#"{"enteredUnit":"ml","leftML":60,"rightML":60}"#.utf8))
        #expect(!old.isTotalOnly)
    }
}
