import Foundation
import NewbeeKit
import Testing
@testable import NewbeeShared

@Suite("Live Activity reconciliation plan")
struct LiveActivityPlannerTests {
    let planner = LiveActivityPlanner()
    let now = t0 + minutes(20)

    @Test func startingASessionRequestsAnActivity() {
        let snapshot = activeOnRight()
        let actions = planner.plan(for: snapshot, existing: [], activitiesEnabled: true, babyName: "Ada", now: now)
        let state = State(snapshot: snapshot)
        #expect(actions == [
            .request(FeedingActivityAttributes(sessionID: sessionID, babyName: "Ada"), state, staleDate: state.staleDate),
        ])
    }

    @Test func nothingIsRequestedWhenLiveActivitiesAreDisabled() {
        #expect(planner.plan(for: activeOnRight(), existing: [], activitiesEnabled: false, now: now).isEmpty)
    }

    @Test func aNewerRevisionUpdatesTheExistingActivity() {
        let shown = State(snapshot: activeOnRight(revision: 2))
        let paused = pausedAfterRight(revision: 3)
        let new = State(snapshot: paused)
        let actions = planner.plan(for: paused, existing: [record("a", state: shown)], activitiesEnabled: true, now: now)
        #expect(actions == [.update(id: "a", new, staleDate: new.staleDate)])
    }

    @Test func anUnchangedSnapshotDoesNothing() {
        // e.g. the app was killed and relaunched; the activity is already right.
        let snapshot = activeOnRight()
        let actions = planner.plan(
            for: snapshot, existing: [record("a", state: State(snapshot: snapshot))], activitiesEnabled: true, now: now
        )
        #expect(actions.isEmpty)
    }

    @Test func neverMovesAnActivityBackToAnOlderRevision() {
        let newer = State(snapshot: pausedAfterRight(revision: 9))
        let actions = planner.plan(
            for: activeOnRight(revision: 2), existing: [record("a", state: newer)], activitiesEnabled: true, now: now
        )
        #expect(actions.isEmpty)
    }

    @Test func endingShowsTheFinalSummaryThenDismisses() {
        let shown = State(snapshot: activeOnRight())
        let completed = completedSpecExample()
        let actions = planner.plan(for: completed, existing: [record("a", state: shown)], activitiesEnabled: true, now: now)
        #expect(actions == [
            .end(id: "a", finalState: State(snapshot: completed), dismissal: .after(now + minutes(15))),
        ])
    }

    @Test func endingWithNoActivityDoesNotRequestOne() {
        #expect(planner.plan(for: completedSpecExample(), existing: [], activitiesEnabled: true, now: now).isEmpty)
    }

    @Test func discardingEndsEverythingImmediately() {
        let shown = State(snapshot: activeOnRight())
        let actions = planner.plan(
            for: nil,
            existing: [record("a", state: shown), record("b", session: otherSessionID, state: shown)],
            activitiesEnabled: true, now: now
        )
        #expect(actions == [
            .end(id: "a", finalState: nil, dismissal: .immediate),
            .end(id: "b", finalState: nil, dismissal: .immediate),
        ])
    }

    @Test func activitiesForOtherSessionsAreEnded() {
        let snapshot = activeOnRight()
        let state = State(snapshot: snapshot)
        let actions = planner.plan(
            for: snapshot,
            existing: [record("old", session: otherSessionID, state: state), record("a", state: state)],
            activitiesEnabled: true, now: now
        )
        #expect(actions == [.end(id: "old", finalState: nil, dismissal: .immediate)])
    }

    @Test func duplicateActivitiesForTheSameSessionCollapseToTheNewest() {
        let snapshot = pausedAfterRight(revision: 3)
        let state = State(snapshot: snapshot)
        let older = State(snapshot: activeOnRight(revision: 2))
        let actions = planner.plan(
            for: snapshot, existing: [record("x", state: older), record("y", state: state)], activitiesEnabled: true, now: now
        )
        #expect(actions == [.end(id: "x", finalState: nil, dismissal: .immediate)])
    }

    @Test func goneAfterRebootOrExpiryIsRequestedAgain() {
        let snapshot = activeOnRight()
        let ended = record("a", state: State(snapshot: snapshot), phase: .finished)
        let actions = planner.plan(for: snapshot, existing: [ended], activitiesEnabled: true, now: now)
        guard case .request = actions.first else {
            Issue.record("expected a request, got \(actions)")
            return
        }
        #expect(actions.count == 1)
    }

    @Test func respectsTheParentDismissingItUntilTheSessionChanges() {
        let snapshot = activeOnRight(revision: 4)
        #expect(planner.plan(for: snapshot, existing: [], activitiesEnabled: true, dismissedAtRevision: 4, now: now).isEmpty)
        let changed = pausedAfterRight(revision: 5)
        #expect(planner.plan(for: changed, existing: [], activitiesEnabled: true, dismissedAtRevision: 4, now: now).count == 1)
    }

    @Test func customEndedSummaryDuration() {
        let planner = LiveActivityPlanner(endedSummaryDuration: 0)
        let actions = planner.plan(
            for: completedSpecExample(), existing: [record("a", state: State(snapshot: activeOnRight()))],
            activitiesEnabled: true, now: now
        )
        #expect(actions == [.end(id: "a", finalState: State(snapshot: completedSpecExample()), dismissal: .after(now))])
    }
}
