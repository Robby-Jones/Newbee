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

        // End from the Lock Screen: summary shown, then Undo in the app.
        let beforeEnd = try #require(manager.activeSession)
        await manager.handleLiveActivityCommand(.end, sessionID: id)
        #expect(manager.activeSession == nil)
        #expect(client.activities[0].phase == .ended)
        #expect(client.activities[0].state.status == .ended)

        try manager.restore(beforeEnd)
        await manager.waitForPendingEffects()
        let visible = client.activities.filter { $0.phase != .dismissed }
        #expect(visible.count == 1)
        #expect(visible.first?.state.status == .paused)
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
