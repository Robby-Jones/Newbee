import Foundation
import NewbeeKit
import Testing
@testable import NewbeeShared

@Suite("ContentState mapping from SessionSnapshot")
struct ContentStateMappingTests {
    @Test func activeSessionTicksFromOpenSegment() {
        let state = State(snapshot: activeOnRight())
        #expect(state.status == .active)
        #expect(state.currentSide == .right)
        #expect(state.sessionStart == t0)
        #expect(state.currentSegmentStart == t0 + minutes(12))
        #expect(state.leftAccumulated == minutes(12))
        #expect(state.rightAccumulated == 0)
        #expect(state.pausedAt == nil)
        #expect(state.revision == 2)
    }

    @Test func timerStartsAreShiftedByAccumulatedTime() {
        // Second right segment: right already has 5 min, left has 12.
        let snapshot = SessionSnapshot(
            id: sessionID, status: .active,
            segments: [
                Segment(side: .left, start: t0, end: t0 + minutes(12)),
                Segment(side: .right, start: t0 + minutes(12), end: t0 + minutes(17)),
                Segment(side: .right, start: t0 + minutes(20)),
            ],
            startedAt: t0, revision: 5
        )
        let state = State(snapshot: snapshot)
        #expect(state.runningSideTimerStart == t0 + minutes(15))   // 20 − 5
        #expect(state.runningTotalTimerStart == t0 + minutes(3))   // 20 − 17
        // At t0+22m: right = 5 + 2, total = 17 + 2 (the 3-minute pause excluded).
        let now = t0 + minutes(22)
        #expect(state.duration(on: .right, at: now) == minutes(7))
        #expect(state.duration(on: .left, at: now) == minutes(12))
        #expect(state.total(at: now) == minutes(19))
        #expect(now.timeIntervalSince(state.runningTotalTimerStart!) == state.total(at: now))
        #expect(now.timeIntervalSince(state.runningSideTimerStart!) == state.duration(on: .right, at: now))
    }

    @Test func pausedSessionIsFrozen() {
        let state = State(snapshot: pausedAfterRight())
        #expect(state.status == .paused)
        #expect(state.currentSide == .right)
        #expect(state.currentSegmentStart == nil)
        #expect(state.runningTotalTimerStart == nil)
        #expect(state.pausedAt == t0 + minutes(17))
        #expect(state.leftAccumulated == minutes(12))
        #expect(state.rightAccumulated == minutes(5))
        #expect(state.total(at: t0 + minutes(90)) == minutes(17))
    }

    @Test func completedSessionMatchesSpecExample() {
        let state = State(snapshot: completedSpecExample())
        #expect(state.status == .ended)
        #expect(state.currentSide == .right)
        #expect(state.leftAccumulated == minutes(12))
        #expect(state.rightAccumulated == minutes(9))
        #expect(state.totalAccumulated == minutes(21))
        #expect(state.pausedAt == t0 + minutes(21))
        #expect(!state.isRunning(.right))
    }

    @Test func activeWithoutOpenSegmentIsShownPausedNotTickingFromAWrongStart() {
        var snapshot = pausedAfterRight()
        snapshot.status = .active
        let state = State(snapshot: snapshot)
        #expect(state.status == .paused)
        #expect(state.currentSegmentStart == nil)
        #expect(state.totalAccumulated == minutes(17))
    }

    @Test func completedWithLeftoverOpenSegmentCountsUpToEnd() {
        var snapshot = activeOnRight()
        snapshot.status = .completed
        snapshot.endedAt = t0 + minutes(20)
        let state = State(snapshot: snapshot)
        #expect(state.status == .ended)
        #expect(state.rightAccumulated == minutes(8))
        #expect(state.totalAccumulated == minutes(20))
    }

    @Test func sessionCrossingMidnightUsesAbsoluteTime() {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: 6, hour: 23, minute: 55)
        let start = calendar.date(from: comps)!
        comps.day = 7; comps.hour = 0; comps.minute = 4
        let switchAt = calendar.date(from: comps)!
        let snapshot = SessionSnapshot(
            id: sessionID, status: .active,
            segments: [Segment(side: .left, start: start, end: switchAt), Segment(side: .right, start: switchAt)],
            startedAt: start, revision: 2
        )
        let state = State(snapshot: snapshot)
        #expect(state.leftAccumulated == minutes(9))
        #expect(state.total(at: switchAt + minutes(1)) == minutes(10))
    }

    @Test func staleDateIsTheStillFeedingThresholdAfterTheLastChange() {
        // Running: measured from the open segment's start, like the in-app recovery prompt.
        #expect(State(snapshot: activeOnRight()).staleDate(after: minutes(45)) == t0 + minutes(12 + 45))
        // Paused: measured from the pause.
        #expect(State(snapshot: pausedAfterRight()).staleDate(after: minutes(45)) == t0 + minutes(17 + 45))
    }

    @Test func payloadIsWellUnderTheFourKilobyteLimit() throws {
        let data = try JSONEncoder().encode(State(snapshot: activeOnRight()))
        #expect(data.count < 400)
        let decoded = try JSONDecoder().decode(State.self, from: data)
        #expect(decoded == State(snapshot: activeOnRight()))
    }
}
