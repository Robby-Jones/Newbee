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

    @Test func anExpiredActivityCountingFromAnOlderFeedIsRemoved() {
        // It hit the limit while counting from the previous feed; a newer feed has ended since.
        var older = completedSpecExample()
        older.id = otherSessionID
        let expired = record("old", session: otherSessionID, state: State(snapshot: older), phase: .ended)
        #expect(planner.plan(for: completedSpecExample(), existing: [expired], activitiesEnabled: true, now: now) == [
            .end(id: "old", finalState: nil, dismissal: .immediate),
        ])
    }

    @Test func theNextFeedReplacesTheSinceLastFeedCountNotAnOlderLeftover() {
        // Revisions are per session, so a leftover's higher revision must not win.
        let thirdID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        var previous = completedSpecExample(revision: 3)
        previous.id = otherSessionID
        var leftover = activeOnRight(revision: 7)
        leftover.id = thirdID
        leftover.startedAt = t0 - 6 * 3600
        let snapshot = SessionSnapshot(
            id: sessionID, status: .active, segments: [Segment(side: .left, start: t0 + minutes(90))],
            startedAt: t0 + minutes(90), revision: 1
        )
        let state = State(snapshot: snapshot)
        let actions = planner.plan(
            for: snapshot,
            existing: [
                record("leftover", session: thirdID, state: State(snapshot: leftover)),
                record("count", session: otherSessionID, state: State(snapshot: previous)),
            ],
            activitiesEnabled: true, now: now
        )
        #expect(actions == [
            .end(id: "leftover", finalState: nil, dismissal: .immediate),
            .request(
                FeedingActivityAttributes(sessionID: sessionID, babyName: ""), state,
                staleDate: state.staleDate(after: minutes(45)), replacing: "count"
            ),
        ])
    }

    @Test func aCarriedOverActivityIsSwappedForAFreshOneAtTheNextSync() {
        // Start on the Lock Screen carried the old activity over to this feed; the app is now in
        // the foreground, so it can get one with its own 8-hour clock.
        let snapshot = activeOnRight(revision: 2)
        let state = State(snapshot: snapshot)
        let carried = LiveActivityRecord(
            id: "old", sessionID: sessionID, requestedForSessionID: otherSessionID, state: state, phase: .live
        )
        #expect(carried.isCarriedOver)
        #expect(planner.plan(for: snapshot, existing: [carried], activitiesEnabled: true, now: now) == [
            .request(
                FeedingActivityAttributes(sessionID: sessionID, babyName: ""), state,
                staleDate: state.staleDate(after: minutes(45)), replacing: "old"
            ),
        ])
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

    // MARK: Bottles

    /// 90 mL, started `start` minutes after t0 and lasting `duration` minutes.
    func bottle(at start: Double, for duration: Double? = 10, id: UUID = bottleID) -> BottleEntry {
        BottleEntry(
            id: id, startedAt: t0 + minutes(start), contents: .formula, amountML: 90,
            durationSeconds: duration.map(minutes)
        )
    }

    func idle(_ actions: [LiveActivityAction]) -> State? {
        guard actions.count == 1, case let .update(id: "a", state, staleDate: _) = actions[0] else { return nil }
        return state
    }

    @Test func aBottleAfterTheLastBreastfeedTakesOverTheCount() throws {
        let completed = completedSpecExample()
        let shown = record("a", state: State(snapshot: completed))
        let later = bottle(at: 60)
        let state = try #require(idle(planner.plan(
            for: completed, lastBottle: later, existing: [shown], activitiesEnabled: true, now: now
        )))
        #expect(state.sessionID == bottleID)
        #expect(state.lastFeedEndedAt == t0 + minutes(70))
        #expect(state.lastBottle == BottleAmount(90, .milliliters))
        #expect(state.totalAccumulated == 0)
        // Start still suggests the other breast from the last breastfeed (it ended on the right).
        #expect(state.currentSide == .right)
        #expect(state == State(bottle: later, lastBreastSide: .right))
    }

    @Test func aBottleWithNoDurationCountsFromItsStart() throws {
        let shown = record("a", state: State(snapshot: completedSpecExample()))
        let state = try #require(idle(planner.plan(
            for: completedSpecExample(), lastBottle: bottle(at: 60, for: nil), existing: [shown], activitiesEnabled: true, now: now
        )))
        #expect(state.lastFeedEndedAt == t0 + minutes(60))
    }

    @Test func aBottleOlderThanTheLastBreastfeedChangesNothing() {
        let completed = completedSpecExample()
        let shown = record("a", state: State(snapshot: completed))
        // Logged afterwards, but with an earlier time: it isn't the latest feed.
        #expect(planner.plan(
            for: completed, lastBottle: bottle(at: -90), existing: [shown], activitiesEnabled: true, now: now
        ).isEmpty)
        // Started at the same moment: the breastfeed wins, as for reminders.
        #expect(planner.plan(
            for: completed, lastBottle: bottle(at: 0), existing: [shown], activitiesEnabled: true, now: now
        ).isEmpty)
    }

    @Test func deletingTheBottleGoesBackToTheBreastfeed() throws {
        let completed = completedSpecExample()
        let shown = record("a", state: State(bottle: bottle(at: 60), lastBreastSide: .right))
        let state = try #require(idle(planner.plan(for: completed, lastBottle: nil, existing: [shown], activitiesEnabled: true, now: now)))
        #expect(state == State(snapshot: completed))
    }

    @Test func deletingTheBottleGoesBackToAnOlderBottle() throws {
        // The repository's next latest bottle is passed in; it may still be newer than the breastfeed.
        let shown = record("a", state: State(bottle: bottle(at: 60), lastBreastSide: .right))
        let older = bottle(at: 40, id: otherBottleID)
        let state = try #require(idle(planner.plan(
            for: completedSpecExample(), lastBottle: older, existing: [shown], activitiesEnabled: true, now: now
        )))
        #expect(state.sessionID == otherBottleID)
        #expect(state.lastFeedEndedAt == t0 + minutes(50))
    }

    @Test func editingTheBottlesTimeMovesTheCount() throws {
        let completed = completedSpecExample()
        let shown = record("a", state: State(bottle: bottle(at: 60), lastBreastSide: .right))
        // Moved later: same bottle, new end.
        let moved = try #require(idle(planner.plan(
            for: completed, lastBottle: bottle(at: 90, for: 15), existing: [shown], activitiesEnabled: true, now: now
        )))
        #expect(moved.sessionID == bottleID)
        #expect(moved.lastFeedEndedAt == t0 + minutes(105))
        // Moved before the breastfeed: the breastfeed is the latest again.
        let back = try #require(idle(planner.plan(
            for: completed, lastBottle: bottle(at: -60), existing: [shown], activitiesEnabled: true, now: now
        )))
        #expect(back == State(snapshot: completed))
    }

    @Test func aBreastfeedAddedAfterTheBottleTakesTheCountBack() throws {
        // e.g. a breastfeed added from History with a later start than the bottle.
        let shown = record("a", state: State(bottle: bottle(at: 60), lastBreastSide: .right))
        var added = completedSpecExample()
        added.id = otherSessionID
        added.startedAt = t0 + minutes(80)
        added.segments = [Segment(side: .left, start: t0 + minutes(80), end: t0 + minutes(95))]
        added.endedAt = t0 + minutes(95)
        let state = try #require(idle(planner.plan(
            for: added, lastBottle: bottle(at: 60), existing: [shown], activitiesEnabled: true, now: now
        )))
        #expect(state.sessionID == otherSessionID)
        #expect(state.lastFeedEndedAt == t0 + minutes(95))
        #expect(state.lastBottle == nil)
    }

    @Test func withOnlyBottlesTheCountFollowsTheLatestBottle() throws {
        let shown = record("a", state: State(bottle: bottle(at: 60), lastBreastSide: nil))
        #expect(planner.plan(for: nil, lastBottle: bottle(at: 60), existing: [shown], activitiesEnabled: true, now: now).isEmpty)
        let state = try #require(idle(planner.plan(
            for: nil, lastBottle: bottle(at: 30, id: otherBottleID), existing: [shown], activitiesEnabled: true, now: now
        )))
        #expect(state.sessionID == otherBottleID)
        #expect(state.currentSide == .left)
        // The last bottle deleted too: no feeds left.
        #expect(planner.plan(for: nil, lastBottle: nil, existing: [shown], activitiesEnabled: true, now: now) == [
            .end(id: "a", finalState: nil, dismissal: .immediate),
        ])
    }

    @Test func aBottleNeverRequestsAnActivityOnItsOwn() {
        #expect(planner.plan(for: completedSpecExample(), lastBottle: bottle(at: 60), existing: [], activitiesEnabled: true, now: now).isEmpty)
    }

    @Test func aBottleDoesntChangeARunningFeed() {
        let snapshot = activeOnRight()
        let shown = record("a", state: State(snapshot: snapshot))
        #expect(planner.plan(for: snapshot, lastBottle: bottle(at: 60), existing: [shown], activitiesEnabled: true, now: now).isEmpty)
    }

    @Test func theNextFeedReplacesACountSinceABottle() {
        let shown = record("a", state: State(bottle: bottle(at: 60), lastBreastSide: .right))
        var next = activeOnRight(revision: 1)
        next.id = otherSessionID
        let actions = planner.plan(for: next, lastBottle: bottle(at: 60), existing: [shown], activitiesEnabled: true, now: now)
        let state = State(snapshot: next)
        #expect(actions == [
            .request(
                FeedingActivityAttributes(sessionID: otherSessionID, babyName: ""), state,
                staleDate: state.staleDate(after: minutes(45)), replacing: "a"
            ),
        ])
    }

    @Test func anExpiredCountSinceTheSameBottleIsLeftToTimeOut() {
        let b = bottle(at: 60)
        let expired = record("a", session: bottleID, state: State(bottle: b, lastBreastSide: .right), phase: .ended)
        #expect(planner.plan(for: completedSpecExample(), lastBottle: b, existing: [expired], activitiesEnabled: true, now: now).isEmpty)
        // Edited since: it shows the wrong time, so it goes.
        #expect(planner.plan(
            for: completedSpecExample(), lastBottle: bottle(at: 70), existing: [expired], activitiesEnabled: true, now: now
        ) == [.end(id: "a", finalState: nil, dismissal: .immediate)])
    }

    // MARK: Appearance

    @Test func theAppsAppearanceIsCarriedAndAChangeUpdatesTheActivity() throws {
        let snapshot = activeOnRight()
        let shown = record("a", state: State(snapshot: snapshot))
        // System is the default and leaves content as it was.
        #expect(planner.plan(for: snapshot, existing: [shown], activitiesEnabled: true, appearance: .system, now: now).isEmpty)
        let dark = try #require(idle(planner.plan(for: snapshot, existing: [shown], activitiesEnabled: true, appearance: .dark, now: now)))
        #expect(dark.appearance == .dark)
        #expect(dark.status == .active)

        let completed = completedSpecExample()
        let counting = record("a", state: State(snapshot: completed))
        let light = try #require(idle(planner.plan(for: completed, existing: [counting], activitiesEnabled: true, appearance: .light, now: now)))
        #expect(light.appearance == .light)
        #expect(light.status == .ended)
    }
}
