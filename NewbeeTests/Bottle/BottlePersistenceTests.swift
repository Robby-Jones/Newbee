import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// Bottle feeds against a real SwiftData store.
@MainActor
@Suite("Bottle persistence")
struct BottlePersistenceTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func makeRepository() throws -> (ModelContainer, SwiftDataBottleRepository) {
        let container = try makeInMemoryContainer()
        return (container, SwiftDataBottleRepository(container: container))
    }

    @Test func entryRoundTripsExactly() throws {
        let (container, repository) = try makeRepository()
        let entry = BottleEntry(
            startedAt: start,
            contents: .formula,
            amountML: BottleAmount(3, .fluidOunces).milliliters,
            enteredUnit: .fluidOunces,
            durationSeconds: 600,
            notes: "spat up a little",
            timeZoneID: "Europe/London"
        )
        try repository.save(entry, modifiedAt: start)
        #expect(try repository.bottle(id: entry.id) == entry)

        // Stored the way docs/DATA_MODEL.md describes: a completed bottle session, no segments.
        let session = try #require(try container.mainContext.fetch(FetchDescriptor<FeedingSession>()).first)
        #expect(session.kind == .bottle)
        #expect(session.status == .completed)
        #expect(session.source == .manual)
        #expect(session.endedAt == start.addingTimeInterval(600))
        #expect((session.segments ?? []).isEmpty)
        #expect(session.bottle?.amountML == entry.amountML)
    }

    @Test func savingAgainEditsInPlace() throws {
        let (container, repository) = try makeRepository()
        var entry = BottleEntry(startedAt: start, contents: .formula, amountML: 90)
        try repository.save(entry, modifiedAt: start)
        entry.amountML = 120
        entry.contents = .breastMilk
        entry.durationSeconds = nil
        try repository.save(entry, modifiedAt: start.addingTimeInterval(60))

        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSession>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<BottleDetails>()) == 1)
        #expect(try repository.bottle(id: entry.id) == entry)
    }

    @Test func deleteRemovesTheSessionAndItsDetails() throws {
        let (container, repository) = try makeRepository()
        let entry = BottleEntry(startedAt: start, contents: .formula, amountML: 90)
        try repository.save(entry, modifiedAt: start)
        try repository.deleteBottle(id: entry.id)
        try repository.deleteBottle(id: entry.id)

        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSession>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<BottleDetails>()) == 0)
    }

    @Test func queriesSeeOnlyBottlesInRange() throws {
        let (container, repository) = try makeRepository()
        let early = BottleEntry(startedAt: start, contents: .formula, amountML: 60)
        let late = BottleEntry(startedAt: start.addingTimeInterval(3600), contents: .breastMilk, amountML: 90)
        try repository.save(late, modifiedAt: start)
        try repository.save(early, modifiedAt: start)
        // A breastfeed in the same window must not show up as a bottle.
        container.mainContext.insert(FeedingSession(kind: .breast, status: .completed, startedAt: start.addingTimeInterval(60)))
        try container.mainContext.save()

        #expect(try repository.recentBottles(limit: 5).map(\.id) == [late.id, early.id])
        #expect(try repository.recentBottles(limit: 1).map(\.id) == [late.id])
        let window = DateInterval(start: start, end: start.addingTimeInterval(3600))
        #expect(try repository.bottles(startingIn: window).map(\.id) == [early.id])
    }

    @Test func bottlesDontDisturbTheBreastfeedingTimer() throws {
        let container = try makeInMemoryContainer()
        let bottles = SwiftDataBottleRepository(container: container)
        let sessions = SwiftDataFeedingRepository(container: container)
        try bottles.save(BottleEntry(startedAt: start, contents: .formula, amountML: 90), modifiedAt: start)

        #expect(try sessions.openSessions().isEmpty)
        #expect(try sessions.recentCompletedSessions(limit: 5).isEmpty)
    }

    @Test func newBottlesAttachToTheBabyProfile() throws {
        let (container, repository) = try makeRepository()
        container.mainContext.insert(Baby(name: "Ada"))
        try container.mainContext.save()
        let entry = BottleEntry(startedAt: start, contents: .formula, amountML: 90)
        try repository.save(entry, modifiedAt: start)

        let session = try #require(try container.mainContext.fetch(FetchDescriptor<FeedingSession>()).first)
        #expect(session.baby?.name == "Ada")
    }
}

/// The view model's save, delete and undo flow on a real store.
@MainActor
@Suite("Bottle log UI model")
struct BottleLogUIModelTests {
    func makeModel(clock: TestClock = TestClock()) throws -> (BottleLogUIModel, ModelContainer) {
        let container = try makeInMemoryContainer()
        let log = BottleLog(repository: SwiftDataBottleRepository(container: container), clock: clock)
        let defaults = try #require(UserDefaults(suiteName: "BottleLogUIModelTests-\(UUID().uuidString)"))
        return (BottleLogUIModel(log: log, preferences: AppPreferences(defaults: defaults, locale: Locale(identifier: "en_GB"))), container)
    }

    @Test func presetSavePathAndUndo() throws {
        let (model, _) = try makeModel()
        #expect(model.unit == .milliliters)
        model.presentNew()
        var draft = try #require(model.editor?.draft)
        draft.amount = model.presets[2]
        draft.contents = .formula

        #expect(model.save(draft))
        #expect(model.editor == nil)
        #expect(model.recent.count == 1)
        #expect(model.today.totalML == 120)
        #expect(model.toast?.message == "Bottle saved · 120 mL formula")

        model.undo()
        #expect(model.recent.isEmpty)
        #expect(model.toast == nil)
    }

    @Test func savingInOuncesRemembersTheUnit() throws {
        let (model, _) = try makeModel()
        model.presentNew()
        var draft = try #require(model.editor?.draft)
        draft.amount = BottleAmount(4, .fluidOunces)
        #expect(model.save(draft))
        #expect(model.unit == .fluidOunces)
        #expect(model.presets.map(\.value) == [2, 3, 4])
        model.presentNew()
        #expect(model.editor?.draft.amount == BottleAmount(4, .fluidOunces))
    }

    @Test func invalidDraftStaysOpenWithAMessage() throws {
        let (model, _) = try makeModel()
        model.presentNew()
        var draft = try #require(model.editor?.draft)
        draft.amount = BottleAmount(900, .milliliters)
        #expect(!model.save(draft))
        #expect(model.editor != nil)
        #expect(model.errorMessage != nil)
        #expect(model.recent.isEmpty)
    }

    @Test func editAndDeleteWithUndo() throws {
        let (model, _) = try makeModel()
        model.presentNew()
        let draft = try #require(model.editor?.draft)
        #expect(model.save(draft))
        let id = try #require(model.recent.first?.id)

        model.presentEdit(sessionID: id)
        var edit = try #require(model.editor?.draft)
        #expect(edit.id == id)
        edit.amount = BottleAmount(60, .milliliters)
        #expect(model.save(edit))
        #expect(model.recent.first?.amountML == 60)
        model.undo()
        #expect(model.recent.first?.amountML == 90)

        model.delete(id: id)
        #expect(model.recent.isEmpty)
        model.undo()
        #expect(model.recent.map(\.id) == [id])
    }

    @Test func editingAMissingEntryShowsAnError() throws {
        let (model, _) = try makeModel()
        model.presentEdit(sessionID: UUID())
        #expect(model.editor == nil)
        #expect(model.errorMessage != nil)
    }
}
