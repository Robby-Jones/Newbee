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
        #expect(client.calls.last == .end(id: "activity-1", final: .ended, dismissal: .after(clock.now + 15 * 60)))
        #expect(client.activities[0].state.totalAccumulated == 21 * 60)
        #expect(client.calls.count == 3)
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

    @Test func undoOfEndLeavesOnlyOneActivityOnScreen() async {
        let coordinator = makeCoordinator()
        let start = clock.now
        await coordinator.sync(active(on: .left, revision: 1, since: start))
        clock.advance(by: 600)
        let completed = SessionSnapshot(
            id: id, status: .completed, segments: [Segment(side: .left, start: start, end: clock.now)],
            startedAt: start, endedAt: clock.now, revision: 2
        )
        await coordinator.sync(completed) // summary stays visible for 15 min
        let restored = SessionSnapshot(
            id: id, status: .active, segments: [Segment(side: .left, start: start)], startedAt: start, revision: 3
        )
        await coordinator.sync(restored) // Undo in the app
        let visible = client.activities.filter { $0.phase != .dismissed }
        #expect(visible.count == 1)
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
        #expect(client.calls.contains(.end(id: "activity-1", final: nil, dismissal: .immediate)))
        #expect(client.calls.last == .request(sessionID: id, revision: 1))
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
