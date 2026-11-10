import Foundation
import Testing
@testable import NewbeeKit

/// Amounts are shown in the unit setting, past entries included, and pumping has its own presets.
@Suite("Unit settings")
@MainActor
struct UnitSettingTests {
    let clock = TestClock()

    @Test func pumpPresetsHaveTheirOwnDefaultsAndLimits() {
        #expect(PumpPresets.defaults(for: .milliliters).map(\.value) == [30, 60, 90])
        #expect(PumpPresets.defaults(for: .fluidOunces).map(\.value) == [1, 2, 3])
        #expect(PumpPresets.amounts(storedML: nil, unit: .fluidOunces) == PumpPresets.defaults(for: .fluidOunces))
        #expect(PumpPresets.amounts(storedML: [90, 0, 30, 900, 30], unit: .milliliters).map(\.value) == [30, 90])
        #expect(PumpPresets.editable(storedML: [90, 30, 30], unit: .milliliters).map(\.value) == [90, 30, 30])
        #expect(PumpPresets.editable(storedML: [59.147059125], unit: .fluidOunces) == [BottleAmount(2, .fluidOunces)])
        #expect(PumpPresets.nextAmount(after: [BottleAmount(3, .fluidOunces)], unit: .fluidOunces) == BottleAmount(4, .fluidOunces))
    }

    @Test func entriesShowInAnyUnit() {
        let bottle = BottleEntry(startedAt: clock.now, contents: .formula, amountML: 90, enteredUnit: .milliliters)
        #expect(bottle.amount(in: .fluidOunces) == BottleAmount(3, .fluidOunces))
        #expect(bottle.enteredAmount == BottleAmount(90, .milliliters))

        let pump = PumpEntry(startedAt: clock.now, leftML: 59.147059125, rightML: 29.5735295625, enteredUnit: .fluidOunces)
        #expect(pump.amount(on: .left, in: .milliliters) == BottleAmount(59, .milliliters))
        #expect(pump.totalAmount(in: .milliliters) == BottleAmount(89, .milliliters))
        #expect(pump.amount(on: .right) == BottleAmount(1, .fluidOunces))
    }

    @Test func editingABottleInAnotherUnitKeepsItsExactAmountUntilChanged() throws {
        let repository = InMemoryBottleRepository()
        let log = BottleLog(repository: repository, clock: clock)
        let saved = try log.save(BottleDraft(contents: .breastMilk, amount: BottleAmount(90, .milliliters), startedAt: clock.now)).saved

        var draft = try #require(try log.editDraft(id: saved.id, unit: .fluidOunces))
        #expect(draft.amount == BottleAmount(3, .fluidOunces))
        draft.notes = "sleepy"
        let unchanged = try log.save(draft).saved
        #expect(unchanged.amountML == 90)
        #expect(unchanged.enteredUnit == .fluidOunces)

        // Switching units back and forth on the sheet doesn't drift either.
        draft.convert(to: .milliliters)
        #expect(draft.amount == BottleAmount(90, .milliliters))
        draft.convert(to: .fluidOunces)
        draft.amount = BottleAmount(4, .fluidOunces)
        let changed = try log.save(draft).saved
        #expect(abs(changed.amountML - 118.29411825) < 1e-6)
    }

    @Test func editingPumpingInAnotherUnitKeepsExactAmountsUntilChanged() throws {
        let repository = InMemoryPumpRepository()
        let log = PumpLog(repository: repository, clock: clock)
        let saved = try log.save(PumpDraft(
            left: BottleAmount(70, .milliliters),
            right: BottleAmount(50, .milliliters),
            startedAt: clock.now.addingTimeInterval(-3600)
        )).saved

        var draft = try #require(try log.editDraft(id: saved.id, unit: .fluidOunces))
        #expect(draft.left == BottleAmount(2.4, .fluidOunces))
        #expect(draft.right == BottleAmount(1.7, .fluidOunces))
        draft.setAmount(BottleAmount(2, .fluidOunces), on: .right)
        let edited = try log.save(draft).saved
        #expect(edited.leftML == 70)
        #expect(abs(edited.rightML - 59.147059125) < 1e-6)
        #expect(edited.enteredUnit == .fluidOunces)

        draft.convert(to: .milliliters)
        #expect(draft.left == BottleAmount(70, .milliliters))
    }

    @Test func amountMatchesAtDisplayPrecision() {
        #expect(BottleAmount(3, .fluidOunces).matches(BottleAmount(3.0, .fluidOunces)))
        #expect(!BottleAmount(3, .fluidOunces).matches(BottleAmount(3.1, .fluidOunces)))
        #expect(!BottleAmount(3, .fluidOunces).matches(BottleAmount(3, .milliliters)))
    }
}
