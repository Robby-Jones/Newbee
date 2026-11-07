import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// History and Home against a real SwiftData store: mapping, breastfeed delete with undo, manual entry.
/// Bottle delete and undo are covered by the bottle tests (`BottleLogUIModel`).
@MainActor
@Suite("History integration")
struct HistoryIntegrationTests {
    let clock = TestClock()

    func makeStack() throws -> (ModelContainer, FeedingSessionManager, FeedingSessionUIModel) {
        let container = try makeInMemoryContainer()
        let manager = FeedingSessionManager(repository: SwiftDataFeedingRepository(container: container), clock: clock)
        let model = FeedingSessionUIModel(controller: manager)
        return (container, manager, model)
    }

    @discardableResult
    func insertBottle(_ context: ModelContext, at start: Date, ml: Double = 90) throws -> FeedingSession {
        let session = FeedingSession(kind: .bottle, status: .completed, startedAt: start, source: .manual)
        session.endedAt = start
        session.notes = "warm"
        context.insert(session)
        let details = BottleDetails(contents: .formula, amountML: ml, enteredUnit: .fluidOunces)
        context.insert(details)
        session.bottle = details
        try context.save()
        return session
    }

    func completedEntries(_ container: ModelContainer) throws -> [FeedEntry] {
        try container.mainContext.fetch(FeedingSession.completedFeeds()).compactMap(\.feedEntry)
    }

    @Test func mapsBreastAndBottleFeedsNewestFirstAndSkipsTheRunningFeed() throws {
        let (container, manager, _) = try makeStack()
        try manager.start(side: .left)
        clock.advance(by: 12 * 60)
        try manager.switchSide(to: .right)
        clock.advance(by: 9 * 60)
        try manager.end()
        clock.advance(by: 3_600)
        try insertBottle(container.mainContext, at: clock.now)
        clock.advance(by: 3_600)
        try manager.start(side: .left) // running: not in History

        let entries = try completedEntries(container)
        #expect(entries.map(\.kind) == [.bottle, .breast])
        #expect(entries[0].bottleML == 90)
        #expect(entries[0].notes == "warm")
        #expect(entries[0].details == .bottle(BottleSummary(contents: .formula, amountML: 90, enteredUnit: .fluidOunces)))
        #expect(entries[1].breastDuration == 21 * 60)
        #expect(entries[1].lastSide == .right)
    }

    @Test func deletingABreastfeedCanBeUndone() throws {
        let (container, manager, model) = try makeStack()
        try manager.start(side: .left)
        clock.advance(by: 600)
        try manager.end()
        let entry = try #require(try completedEntries(container).first)

        model.deleteFeed(id: entry.id)
        #expect(try completedEntries(container).isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSegment>()) == 0)
        #expect(manager.lastCompletedSession == nil)
        #expect(model.toast != nil)

        model.undo()
        let restored = try completedEntries(container)
        #expect(restored.map(\.id) == [entry.id])
        #expect(restored.first?.breastDuration == entry.breastDuration)
        #expect(manager.lastCompletedSession?.id == entry.id)
        #expect(model.errorMessage == nil)
    }

    @Test func manualBreastfeedIsSavedAsManualAndSuggestsTheOtherSide() throws {
        let (container, manager, model) = try makeStack()
        let draft = SimpleBreastEdit.manualEntry(endingAt: clock.now, firstSide: .left, left: 600, right: 0)
        try model.addManualFeed(draft.newSession())

        let entry = try #require(try completedEntries(container).first)
        #expect(entry.source == .manual)
        #expect(entry.breastDuration == 600)
        #expect(manager.suggestedNextSide == .right)
    }

    @Test func editingABreastfeedMarksItManualAndClearsReview() throws {
        let (container, manager, model) = try makeStack()
        try manager.start(side: .left)
        clock.advance(by: 12 * 60)
        try manager.switchSide(to: .right)
        clock.advance(by: 9 * 60)
        try manager.end()
        let stored = try #require(manager.lastCompletedSession)
        // Edited later, so the longer feed still ends in the past.
        clock.advance(by: 3_600)

        var draft = try #require(SimpleBreastEdit(stored))
        draft.right = 15 * 60
        var edited = draft.apply(to: stored)
        edited.needsReview = false
        try model.saveEdit(edited)

        let entry = try #require(try completedEntries(container).first)
        #expect(entry.breastDuration == 27 * 60)
        #expect(entry.source == .manual)
        #expect(!entry.needsReview)
    }

    @Test func invalidEditIsRejectedAndNothingChanges() throws {
        let (container, manager, model) = try makeStack()
        try manager.start(side: .left)
        clock.advance(by: 600)
        try manager.end()
        let stored = try #require(manager.lastCompletedSession)

        var future = stored
        future.segments[0].end = clock.now.addingTimeInterval(3_600)
        future = SessionEditing.normalizedCompleted(future)
        #expect(throws: FeedingSessionError.self) { try model.saveEdit(future) }
        #expect(try completedEntries(container).first?.breastDuration == 600)
    }
}
