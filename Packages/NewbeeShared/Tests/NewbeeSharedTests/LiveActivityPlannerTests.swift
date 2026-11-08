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

    @Test func endingKeepsTheActivityAndCountsSinceTheFeedEnded() {
        let shown = State(snapshot: activeOnRight())
        let completed = completedSpecExample()
        let idle = State(snapshot: completed)
        let actions = planner.plan(for: completed, existing: [record("a", state: shown)], activitiesEnabled: true, now: now)
        #expect(actions == [.update(id: "a", idle, staleDate: idle.staleDate(after: minutes(45)))])
        #expect(idle.lastFeedEndedAt == t0 + minutes(21))
    }

    @Test func endingWithNoActivityDoesNotRequestOne() {
        #expect(planner.plan(for: completedSpecExample(), existing: [], activitiesEnabled: true, now: now).isEmpty)
    }

    @Test func sinceLastFeedMovesToAnEarlierFeedWhenTheLatestIsDeleted() {
        // The activity counted from the feed that was deleted; it now counts from the one before.
        var earlier = completedSpecExample(revision: 7)
        earlier.id = otherSessionID
        let shown = record("a", state: State(snapshot: completedSpecExample(revision: 9)))
        let state = State(snapshot: earlier)
        let actions = planner.plan(for: earlier, existing: [shown], activitiesEnabled: true, now: now)
        // Different session, so the lower revision doesn't block the update.
        #expect(actions == [.update(id: "a", state, staleDate: state.staleDate(after: minutes(45)))])
        #expect(state.sessionID == otherSessionID)
    }

    @Test func sinceLastFeedClearsExtraActivitiesAndExpiredOnes() {
        let completed = completedSpecExample()
        let idle = State(snapshot: completed)
        let actions = planner.plan(
            for: completed,
            existing: [
                record("expired", session: otherSessionID, state: State(snapshot: activeOnRight()), phase: .ended),
                record("a", state: idle),
                record("extra", session: otherSessionID, state: State(snapshot: activeOnRight())),
            ],
            activitiesEnabled: true, now: now
        )
        #expect(actions == [
            .end(id: "expired", finalState: nil, dismissal: .immediate),
            .end(id: "extra", finalState: nil, dismissal: .immediate),
        ])
    }

    @Test func anExpiredSinceLastFeedActivityIsLeftToTimeOut() {
        // The 8-hour limit ended it; it can't be updated and isn't requested again until the next feed.
        let completed = completedSpecExample()
        let expired = record("a", state: State(snapshot: completed), phase: .ended)
        #expect(planner.plan(for: completed, existing: [expired], activitiesEnabled: true, now: now).isEmpty)
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

    @Test func undoingEndInTheAppPutsTheSameActivityBack() {
        // End switched the activity to since-last-feed; the parent tapped Undo in the app.
        let idle = record("a", state: State(snapshot: completedSpecExample(revision: 3)))
        let restored = activeOnRight(revision: 4)
        let state = State(snapshot: restored)
        let actions = planner.plan(for: restored, existing: [idle], activitiesEnabled: true, now: now)
        #expect(actions == [.update(id: "a", state, staleDate: state.staleDate(after: minutes(45)))])
    }

    @Test func theNextFeedReplacesTheSinceLastFeedActivityWithAFreshOne() {
        // A fresh request restarts ActivityKit's 8-hour clock; the old one is named so the
        // coordinator can end it after, or reuse it if the request is refused.
        var previous = completedSpecExample()
        previous.id = otherSessionID
        let idle = record("old", session: otherSessionID, state: State(snapshot: previous))
        let snapshot = activeOnRight()
        let state = State(snapshot: snapshot)
        let actions = planner.plan(for: snapshot, existing: [idle], activitiesEnabled: true, now: now)
        #expect(actions == [
            .request(
                FeedingActivityAttributes(sessionID: sessionID, babyName: ""), state,
                staleDate: state.staleDate(after: minutes(45)), replacing: "old"
            ),
        ])
    }

    @Test func theNextFeedRemovesTheSinceLastFeedActivityWhenActivitiesAreOff() {
        var previous = completedSpecExample()
        previous.id = otherSessionID
        let idle = record("old", session: otherSessionID, state: State(snapshot: previous))
        let actions = planner.plan(for: activeOnRight(), existing: [idle], activitiesEnabled: false, now: now)
        #expect(actions == [.end(id: "old", finalState: nil, dismissal: .immediate)])
    }

    @Test func startingTheNextFeedRemovesAnOldSummary() {
        // An expired activity, or an older build's "Feed complete" summary, still on screen.
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

    @Test func repeatedSyncOfTheSinceLastFeedStateIsANoOp() {
        let completed = completedSpecExample()
        let idle = record("a", state: State(snapshot: completed))
        #expect(planner.plan(for: completed, existing: [idle], activitiesEnabled: true, now: now).isEmpty)
    }

    @Test func respectsTheParentDismissingItUntilTheSessionChanges() {
        let snapshot = activeOnRight(revision: 4)
        #expect(planner.plan(for: snapshot, existing: [], activitiesEnabled: true, dismissedAtRevision: 4, now: now).isEmpty)
        let changed = pausedAfterRight(revision: 5)
        #expect(planner.plan(for: changed, existing: [], activitiesEnabled: true, dismissedAtRevision: 4, now: now).count == 1)
    }
}
