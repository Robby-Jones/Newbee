import Foundation
import NewbeeKit
import NewbeeShared
import Testing
@testable import Newbee

@MainActor
@Suite("LiveActivityCoordinator")
struct LiveActivityCoordinatorTests {
    let clock = TestClock()
    let client = FakeLiveActivityClient()
    let id = UUID()

    func makeCoordinator() -> LiveActivityCoordinator {
        LiveActivityCoordinator(client: client, clock: clock)
    }

    func active(on side: Side, revision: Int, since start: Date) -> SessionSnapshot {
        SessionSnapshot(id: id, status: .active, segments: [Segment(side: side, start: start)], startedAt: start, revision: revision)
    }

    @Test func fullFeedLifecycle() async {
        let coordinator = makeCoordinator()
        let start = clock.now
        await coordinator.sync(active(on: .left, revision: 1, since: start))
        #expect(client.calls == [.request(sessionID: id, revision: 1)])

        clock.advance(by: 12 * 60)
        let switchAt = clock.now
        let switched = SessionSnapshot(
            id: id, status: .active,
            segments: [Segment(side: .left, start: start, end: switchAt), Segment(side: .right, start: switchAt)],
            startedAt: start, revision: 2
        )
        await coordinator.sync(switched)
        #expect(client.calls.last == .update(id: "activity-1", revision: 2))
        #expect(client.activities[0].state.currentSide == .right)

        clock.advance(by: 9 * 60)
        var completed = switched
        completed.segments[1].end = clock.now
        completed.status = .completed
        completed.endedAt = clock.now
        completed.revision = 3
        await coordinator.sync(completed)
        // The same activity stays and counts the time since the feed ended.
        #expect(client.calls.last == .update(id: "activity-1", revision: 3))
        #expect(client.activities[0].phase == .live)
        #expect(client.activities[0].state.status == .ended)
        #expect(client.activities[0].state.lastFeedEndedAt == clock.now)
        #expect(client.activities[0].state.totalAccumulated == 21 * 60)
        #expect(client.calls.count == 3)

        // The next feed gets a fresh activity (a new 8-hour window), and only then is the old one removed.
        clock.advance(by: 2 * 3600)
        let nextID = UUID()
        let next = SessionSnapshot(id: nextID, status: .active, segments: [Segment(side: .left, start: clock.now)], startedAt: clock.now, revision: 1)
        await coordinator.sync(next)
        #expect(Array(client.calls.suffix(2)) == [
            .request(sessionID: nextID, revision: 1),
            .end(id: "activity-1", final: nil, dismissal: .immediate),
        ])
        #expect(client.activities.filter { $0.phase != .dismissed }.map(\.id) == ["activity-2"])
    }

    @Test func startFromTheLockScreenReusesTheActivityWhenARequestIsRefused() async {
        let coordinator = makeCoordinator()
        let start = clock.now
        await coordinator.sync(active(on: .left, revision: 1, since: start))
        clock.advance(by: 600)
        let completed = SessionSnapshot(
            id: id, status: .completed, segments: [Segment(side: .left, start: start, end: clock.now)],
            startedAt: start, endedAt: clock.now, revision: 2
        )
        await coordinator.sync(completed)

        // Start tapped on the Lock Screen: the app runs in the background and can't request one.
        client.refuseRequests = true
        clock.advance(by: 3600)
        let nextID = UUID()
        let next = SessionSnapshot(id: nextID, status: .active, segments: [Segment(side: .right, start: clock.now)], startedAt: clock.now, revision: 1)
        await coordinator.sync(next)
        let visible = client.activities.filter { $0.phase != .dismissed }
        #expect(visible.map(\.id) == ["activity-1"])
        #expect(visible.first?.state.status == .active)
        #expect(visible.first?.state.sessionID == nextID)
        #expect(visible.first?.sessionID == nextID)

        // Later syncs treat it as the new feed's activity.
        client.clearCalls()
        client.refuseRequests = false
        clock.advance(by: 60)
        var paused = next
        paused.segments[0].end = clock.now
        paused.status = .paused
        paused.revision = 2
        await coordinator.sync(paused)
        #expect(client.calls == [.update(id: "activity-1", revision: 2)])
    }

    @Test func repeatedSyncOfTheSameSnapshotIsANoOp() async {
        let coordinator = makeCoordinator()
        let snapshot = active(on: .left, revision: 1, since: clock.now)
        await coordinator.sync(snapshot)
        await coordinator.sync(snapshot)
        await coordinator.sync(snapshot)
        #expect(client.calls.count == 1)
    }

    @Test func concurrentSyncsAreSerializedAndNeverDuplicateTheActivity() async {
        // Five rapid Lock Screen taps: each intent syncs while the previous update is in flight.
        let coordinator = makeCoordinator()
        let start = clock.now
        await coordinator.sync(active(on: .left, revision: 1, since: start))
        await withTaskGroup(of: Void.self) { group in
            for revision in 2...6 {
                let side: Side = revision.isMultiple(of: 2) ? .right : .left
                let snapshot = active(on: side, revision: revision, since: start)
                group.addTask { await coordinator.sync(snapshot) }
            }
        }
        #expect(client.activities.count == 1)
        #expect(client.activities[0].state.revision == 6)
        #expect(client.calls.filter { if case .request = $0 { true } else { false } }.count == 1)
    }

    @Test func discardEndsImmediately() async {
        let coordinator = makeCoordinator()
        await coordinator.sync(active(on: .left, revision: 1, since: clock.now))
        await coordinator.sync(nil)
        #expect(client.calls.last == .end(id: "activity-1", final: nil, dismissal: .immediate))
    }

    @Test func recoveryReRequestsAfterReboot() async {
        let coordinator = makeCoordinator()
        let snapshot = active(on: .left, revision: 1, since: clock.now)
        await coordinator.sync(snapshot)
        client.systemRemovesAll()
        await coordinator.sync(snapshot)
        #expect(client.calls == [.request(sessionID: id, revision: 1), .request(sessionID: id, revision: 1)])
    }

    @Test func recoveryReplacesAnActivityTheSystemEndedAtEightHours() async {
        let coordinator = makeCoordinator()
        let snapshot = active(on: .left, revision: 1, since: clock.now)
        await coordinator.sync(snapshot)
        clock.advance(by: 8 * 3600 + 60)
        client.systemEndsAll()
        client.clearCalls()
        await coordinator.sync(snapshot)
        #expect(client.calls == [
            .end(id: "activity-1", final: nil, dismissal: .immediate),
            .request(sessionID: id, revision: 1),
        ])
        #expect(client.activities.filter { $0.phase != .dismissed }.count == 1)
    }

    @Test func undoOfEndInTheAppPutsTheSameActivityBack() async {
        let coordinator = makeCoordinator()
        let start = clock.now
        await coordinator.sync(active(on: .left, revision: 1, since: start))
        clock.advance(by: 600)
        let completed = SessionSnapshot(
            id: id, status: .completed, segments: [Segment(side: .left, start: start, end: clock.now)],
            startedAt: start, endedAt: clock.now, revision: 2
        )
        await coordinator.sync(completed) // now counting since this feed
        let restored = SessionSnapshot(
            id: id, status: .active, segments: [Segment(side: .left, start: start)], startedAt: start, revision: 3
        )
        await coordinator.sync(restored) // Undo in the app
        let visible = client.activities.filter { $0.phase != .dismissed }
        #expect(visible.count == 1)
        #expect(visible.first?.id == "activity-1")
        #expect(visible.first?.state.status == .active)
    }

    @Test func respectsUserDismissalUntilTheNextChange() async {
        let coordinator = makeCoordinator()
        let start = clock.now
        await coordinator.sync(active(on: .left, revision: 1, since: start))
        client.userDismisses("activity-1")
        client.clearCalls()

        await coordinator.sync(active(on: .left, revision: 1, since: start)) // foreground recovery
        #expect(client.calls.isEmpty)

        await coordinator.sync(active(on: .right, revision: 2, since: start)) // parent switched in app
        #expect(client.calls == [.request(sessionID: id, revision: 2)])
    }

    @Test func staleActivityFromAnotherSessionIsEnded() async {
        let coordinator = makeCoordinator()
        let otherID = UUID()
        let old = SessionSnapshot(id: otherID, status: .active, segments: [Segment(side: .left, start: clock.now)], startedAt: clock.now, revision: 1)
        await coordinator.sync(old)
        await coordinator.sync(active(on: .right, revision: 1, since: clock.now))
        // The new one is requested first, so the Lock Screen is never empty in between.
        #expect(Array(client.calls.suffix(2)) == [
            .request(sessionID: id, revision: 1),
            .end(id: "activity-1", final: nil, dismissal: .immediate),
        ])
    }

    @Test func disabledActivitiesAreReportedAndNotRequested() async {
        client.areActivitiesEnabled = false
        let coordinator = makeCoordinator()
        #expect(coordinator.activitiesEnabled == false)
        await coordinator.sync(active(on: .left, revision: 1, since: clock.now))
        #expect(client.calls.isEmpty)

        client.onEnablementChange?(true)
        #expect(coordinator.activitiesEnabled)
    }

    @Test func refusedRequestDoesNotThrowOrBlockLaterSyncs() async {
        client.refuseRequests = true
        let coordinator = makeCoordinator()
        let snapshot = active(on: .left, revision: 1, since: clock.now)
        await coordinator.sync(snapshot) // e.g. app in background
        client.refuseRequests = false
        await coordinator.sync(snapshot) // next foreground
        #expect(client.calls == [.request(sessionID: id, revision: 1)])
    }
}
