import Foundation
import NewbeeKit
import NewbeeShared
import Testing
@testable import Newbee

/// The integration between the session manager and the Live Activity
/// (docs/LIVE_ACTIVITIES.md §8), end to end apart from ActivityKit itself.
@MainActor
@Suite("Live Activity wiring")
struct LiveActivityWiringTests {
    @Test func intentRouterIsRegisteredWithTheSharedManagerAtLaunch() {
        // The test host ran `NewbeeApp.init`, the same path as a background launch for an intent.
        let registered = LiveActivityIntentRouter.registeredHandler
        #expect(registered != nil)
        #expect(registered === AppDependencies.shared.sessionManager)
    }

    @Test func appUsesTheCoordinatorForTheOnDiskStore() {
        #expect(AppDependencies.shared.liveActivity is LiveActivityCoordinator)
    }

    @Test func buttonCommandsGoThroughTheManagerAndUpdateTheActivity() async throws {
        let clock = TestClock()
        let client = FakeLiveActivityClient()
        let coordinator = LiveActivityCoordinator(client: client, clock: clock)
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, liveActivity: coordinator)
        let manager = dependencies.sessionManager

        try manager.start(side: .left)
        await manager.waitForPendingEffects()
        let id = try #require(manager.activeSession?.id)
        #expect(client.activities.count == 1)
        #expect(client.activities[0].state.currentSide == .left)

        // Lock Screen: switch to right.
        clock.advance(by: 12 * 60)
        await manager.handleLiveActivityCommand(.switchTo(.right), sessionID: id)
        #expect(manager.activeSession?.openSegment?.side == .right)
        #expect(client.activities[0].state.currentSide == .right)
        #expect(client.activities[0].state.leftAccumulated == 12 * 60)

        // Double-tapped pause: one change.
        clock.advance(by: 60)
        await manager.handleLiveActivityCommand(.pause, sessionID: id)
        let pausedRevision = manager.activeSession?.revision
        await manager.handleLiveActivityCommand(.pause, sessionID: id)
        #expect(manager.activeSession?.revision == pausedRevision)
        #expect(client.activities[0].state.status == .paused)

        // A button from an old activity is ignored.
        await manager.handleLiveActivityCommand(.end, sessionID: UUID())
        #expect(manager.activeSession?.status == .paused)

        // End from the Lock Screen: the same activity now counts since the feed ended.
        let beforeEnd = try #require(manager.activeSession)
        await manager.handleLiveActivityCommand(.end, sessionID: id)
        #expect(manager.activeSession == nil)
        #expect(client.activities[0].phase == .live)
        #expect(client.activities[0].state.status == .ended)
        #expect(client.activities[0].state.lastFeedEndedAt == manager.lastCompletedSession?.endedAt)

        // Opening the app again keeps it.
        await manager.reload()
        #expect(client.activities[0].phase == .live)
        #expect(client.activities[0].state.status == .ended)

        // Undo in the app puts the feed back on the same activity.
        try manager.restore(beforeEnd)
        await manager.waitForPendingEffects()
        let visible = client.activities.filter { $0.phase != .dismissed }
        #expect(visible.count == 1)
        #expect(visible.first?.state.status == .paused)
    }

    @Test func undoOnTheSummaryPutsTheFeedBackOnTheSameActivityPaused() async throws {
        let clock = TestClock()
        let client = FakeLiveActivityClient()
        let coordinator = LiveActivityCoordinator(client: client, clock: clock)
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, liveActivity: coordinator)
        let manager = dependencies.sessionManager

        try manager.start(side: .left)
        clock.advance(by: 10 * 60)
        try manager.end()
        await manager.waitForPendingEffects()
        let ended = try #require(manager.lastCompletedSession)
        #expect(client.activities[0].state.status == .ended)

        clock.advance(by: 30)
        try manager.reopenPaused(sessionID: ended.id)
        await manager.waitForPendingEffects()
        let visible = client.activities.filter { $0.phase != .dismissed }
        #expect(visible.count == 1)
        #expect(visible.first?.sessionID == ended.id)
        #expect(visible.first?.state.status == .paused)
        #expect(visible.first?.state.leftAccumulated == 10 * 60)
    }

    @Test func theCountFollowsTheLatestFeedAsBottlesAndFeedsChange() async throws {
        let clock = TestClock()
        let client = FakeLiveActivityClient()
        let coordinator = LiveActivityCoordinator(client: client, clock: clock)
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, liveActivity: coordinator)
        let manager = dependencies.sessionManager
        let bottles = dependencies.bottleLog
        func shown() -> FeedingActivityAttributes.ContentState? {
            let visible = client.activities.filter { $0.phase == .live }
            return visible.count == 1 ? visible[0].state : nil
        }

        try manager.start(side: .left)
        clock.advance(by: 10 * 60)
        try manager.end()
        await manager.waitForPendingEffects()
        let breastfeed = try #require(manager.lastCompletedSession)
        #expect(shown()?.sessionID == breastfeed.id)

        // A bottle logged after it: the count restarts from the bottle's end.
        clock.advance(by: 30 * 60)
        var draft = bottles.newDraft(unit: .milliliters)
        draft.startedAt = clock.now.addingTimeInterval(-5 * 60)
        draft.durationSeconds = 5 * 60
        let bottle = try bottles.save(draft).saved
        await manager.bottlesDidChange()
        #expect(shown()?.sessionID == bottle.id)
        #expect(shown()?.lastFeedEndedAt == clock.now)
        #expect(shown()?.lastBottle != nil)

        // Edited to before the breastfeed: the breastfeed is the latest again.
        var edit = try #require(try bottles.editDraft(id: bottle.id))
        edit.startedAt = breastfeed.startedAt.addingTimeInterval(-3600)
        let moved = try bottles.save(edit)
        await manager.bottlesDidChange()
        #expect(shown()?.sessionID == breastfeed.id)
        #expect(shown()?.lastFeedEndedAt == breastfeed.endedAt)

        // Undo the edit: back to the bottle.
        try bottles.undo(moved)
        await manager.bottlesDidChange()
        #expect(shown()?.sessionID == bottle.id)

        // A breastfeed added from History after the bottle takes over; deleting it hands back.
        clock.advance(by: 30 * 60)
        let manual = SessionSnapshot(
            status: .completed,
            segments: [Segment(side: .right, start: clock.now.addingTimeInterval(-20 * 60), end: clock.now.addingTimeInterval(-10 * 60))],
            startedAt: clock.now.addingTimeInterval(-20 * 60),
            endedAt: clock.now.addingTimeInterval(-10 * 60),
            revision: 1,
            source: .manual
        )
        try manager.restore(manual)
        await manager.waitForPendingEffects()
        #expect(shown()?.sessionID == manual.id)
        #expect(shown()?.lastFeedEndedAt == manual.endedAt)
        _ = try manager.deleteCompleted(sessionID: manual.id)
        await manager.waitForPendingEffects()
        #expect(shown()?.sessionID == bottle.id)

        // Deleting the bottle goes back to the first breastfeed.
        try bottles.delete(id: bottle.id)
        await manager.bottlesDidChange()
        #expect(shown()?.sessionID == breastfeed.id)
        #expect(shown()?.lastBottle == nil)
        #expect(client.activities.filter { $0.phase == .live }.count == 1)
    }

    @Test func aNewLatestFeedBringsBackTheCountAfterTheParentSwipedItAway() async throws {
        let clock = TestClock()
        let client = FakeLiveActivityClient()
        let coordinator = LiveActivityCoordinator(client: client, clock: clock)
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, liveActivity: coordinator)
        let manager = dependencies.sessionManager
        let bottles = dependencies.bottleLog
        func live() -> [LiveActivityRecord] { client.activities.filter { $0.phase == .live } }

        try manager.start(side: .left)
        clock.advance(by: 10 * 60)
        try manager.end()
        await manager.waitForPendingEffects()
        client.userDismisses(try #require(live().first).id)
        await manager.reload() // opening the app doesn't bring it back
        #expect(live().isEmpty)

        // A bottle logged for earlier than the breastfeed isn't the latest: still nothing.
        var old = bottles.newDraft(unit: .milliliters)
        old.startedAt = clock.now.addingTimeInterval(-3 * 3600)
        let older = try bottles.save(old).saved
        await manager.bottlesDidChange(logged: older.id)
        #expect(live().isEmpty)

        // A bottle logged now is: the count comes back, counting from it.
        clock.advance(by: 30 * 60)
        let bottle = try bottles.save(bottles.newDraft(unit: .milliliters)).saved
        await manager.bottlesDidChange(logged: bottle.id)
        #expect(live().map(\.sessionID) == [bottle.id])

        // Swiped away again; a breastfeed added by hand after the bottle brings it back.
        client.userDismisses(try #require(live().first).id)
        clock.advance(by: 30 * 60)
        let manual = SessionSnapshot(
            status: .completed,
            segments: [Segment(side: .right, start: clock.now.addingTimeInterval(-20 * 60), end: clock.now.addingTimeInterval(-10 * 60))],
            startedAt: clock.now.addingTimeInterval(-20 * 60),
            endedAt: clock.now.addingTimeInterval(-10 * 60),
            revision: 1,
            source: .manual
        )
        try manager.addFeed(manual)
        await manager.waitForPendingEffects()
        #expect(live().map(\.sessionID) == [manual.id])

        // And Settings' Refresh brings it back too.
        client.userDismisses(try #require(live().first).id)
        await manager.refreshLiveActivity()
        #expect(live().map(\.sessionID) == [manual.id])
    }

    @Test func countFromFollowsTheSetting() async throws {
        let clock = TestClock()
        let client = FakeLiveActivityClient()
        let coordinator = LiveActivityCoordinator(client: client, clock: clock)
        let defaults = try #require(UserDefaults(suiteName: "count-from-\(UUID())"))
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, liveActivity: coordinator, defaults: defaults)
        let preferences = dependencies.preferences
        let manager = dependencies.sessionManager

        try manager.start(side: .left)
        clock.advance(by: 10 * 60)
        try manager.end()
        await manager.waitForPendingEffects()
        let feed = try #require(manager.lastCompletedSession)
        // "Start of last feed" is the default.
        #expect(client.activities.last?.state.sinceLastFeedStart == feed.startedAt)

        preferences.reminders.basis = .end
        await manager.reload() // what NewbeeApp does when the setting changes
        #expect(client.activities.last?.state.sinceLastFeedStart == feed.endedAt)
    }

    @Test(arguments: [
        (LiveActivityCommand.switchTo(.left), SessionCommand.switchTo(.left)),
        (.switchTo(.right), .switchTo(.right)),
        (.pause, .pause),
        (.resume, .resume),
        (.end, .end),
    ])
    func commandMapping(button: LiveActivityCommand, engine: SessionCommand) {
        #expect(SessionCommand(button) == engine)
    }
}
