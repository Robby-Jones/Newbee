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
            .request(FeedingActivityAttributes(sessionID: sessionID, babyName: "Ada"), state, staleDate: state.staleDate(after: minutes(45))),
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
        #expect(actions == [.update(id: "a", new, staleDate: new.staleDate(after: minutes(45)))])
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
        let state = State(snapshot: snapshot)
        // After a reboot the old activity is gone entirely.
        let gone = record("a", state: state, phase: .dismissed)
        #expect(planner.plan(for: snapshot, existing: [gone], activitiesEnabled: true, now: now) == [
            .request(FeedingActivityAttributes(sessionID: sessionID, babyName: ""), state, staleDate: state.staleDate(after: minutes(45))),
        ])
        // After the 8-hour limit it may still be on screen in the ended state: replace it.
        let expired = record("a", state: state, phase: .ended)
        let actions = planner.plan(for: snapshot, existing: [expired], activitiesEnabled: true, now: now)
        #expect(actions.count == 2)
        #expect(actions.first == .end(id: "a", finalState: nil, dismissal: .immediate))
        guard case .request = actions.last else {
            Issue.record("expected a request, got \(actions)")
            return
        }
    }

    @Test func undoingEndReplacesTheSummaryInsteadOfShowingTwoActivities() {
        // End left a 15-minute summary on screen; the parent tapped Undo in the app.
        let summary = record("a", state: State(snapshot: completedSpecExample(revision: 3)), phase: .ended)
        let restored = activeOnRight(revision: 4)
        let state = State(snapshot: restored)
        let actions = planner.plan(for: restored, existing: [summary], activitiesEnabled: true, now: now)
        #expect(actions == [
            .end(id: "a", finalState: nil, dismissal: .immediate),
            .request(FeedingActivityAttributes(sessionID: sessionID, babyName: ""), state, staleDate: state.staleDate(after: minutes(45))),
        ])
    }

    @Test func startingTheNextFeedRemovesThePreviousSummary() {
        // Cluster feeding: a new feed starts while the last one's summary is still showing.
        var previous = completedSpecExample()
        previous.id = otherSessionID
        let summary = record("old", session: otherSessionID, state: State(snapshot: previous), phase: .ended)
        let actions = planner.plan(for: activeOnRight(), existing: [summary], activitiesEnabled: true, now: now)
        #expect(actions.first == .end(id: "old", finalState: nil, dismissal: .immediate))
        #expect(actions.count == 2)
    }

    @Test func dismissedActivitiesAreLeftAlone() {
        let gone = record("x", session: otherSessionID, state: State(snapshot: completedSpecExample()), phase: .dismissed)
        #expect(planner.plan(for: nil, existing: [gone], activitiesEnabled: true, now: now).isEmpty)
        #expect(planner.plan(for: completedSpecExample(), existing: [gone], activitiesEnabled: true, now: now).isEmpty)
    }

    @Test func repeatedSyncOfACompletedSessionKeepsItsOwnSummary() {
        let completed = completedSpecExample()
        let summary = record("a", state: State(snapshot: completed), phase: .ended)
        #expect(planner.plan(for: completed, existing: [summary], activitiesEnabled: true, now: now).isEmpty)
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
