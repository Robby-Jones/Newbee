import Foundation
import Testing
@testable import NewbeeKit

@Suite("SessionValidator")
struct SessionValidatorTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func completed(_ segments: [Segment], end: Date? = nil) -> SessionSnapshot {
        SessionSnapshot(status: .completed, segments: segments, startedAt: segments.first?.start ?? t0, endedAt: end ?? segments.last?.end)
    }

    @Test func validCompletedSessionPasses() {
        let s = completed([
            Segment(side: .left, start: t0, end: t0 + 600),
            Segment(side: .right, start: t0 + 600, end: t0 + 900),
        ])
        #expect(SessionValidator.violations(in: s, now: t0 + 1000).isEmpty)
    }

    @Test func detectsOverlapEndBeforeStartAndFuture() {
        let a = Segment(side: .left, start: t0, end: t0 + 600)
        let b = Segment(side: .right, start: t0 + 500, end: t0 + 400)
        let s = completed([a, b], end: t0 + 7200)
        let v = SessionValidator.violations(in: s, now: t0 + 60)
        #expect(v.contains(.segmentsOverlap(a.id, b.id)))
        #expect(v.contains(.segmentEndsBeforeStart(b.id)))
        #expect(v.contains(.inFuture))
    }

    @Test func detectsStatusAndOpenSegmentMismatches() {
        let open = Segment(side: .left, start: t0)
        #expect(SessionValidator.violations(
            in: SessionSnapshot(status: .paused, segments: [open], startedAt: t0), now: t0 + 60
        ).contains(.misplacedOpenSegment))
        #expect(SessionValidator.violations(
            in: SessionSnapshot(status: .active, segments: [Segment(side: .left, start: t0, end: t0 + 1)], startedAt: t0), now: t0 + 60
        ).contains(.activeWithoutOpenSegment))
        #expect(SessionValidator.violations(
            in: SessionSnapshot(status: .completed, segments: [Segment(side: .left, start: t0, end: t0 + 1)], startedAt: t0), now: t0 + 60
        ).contains(.completedWithoutEnd))
        #expect(SessionValidator.violations(
            in: SessionSnapshot(status: .active, segments: [open], startedAt: t0 - 5), now: t0 + 60
        ).contains(.startMismatch))
        #expect(SessionValidator.violations(
            in: SessionSnapshot(status: .active, segments: [], startedAt: t0), now: t0
        ) == [.noSegments])
    }
}

@Suite("RecoveryPlanner")
struct RecoveryPlannerTests {
    let planner = RecoveryPlanner()
    let engine = SessionEngine()

    func started(_ side: Side = .left, clock: TestClock) throws -> SessionSnapshot {
        try engine.apply(.start(side), to: nil, at: clock.instant()).snapshot
    }

    @Test func nothingOpenMeansNothingToDo() {
        let plan = planner.plan(openSessions: [], at: TestClock().instant())
        #expect(plan.survivor == nil)
        #expect(plan.updates.isEmpty)
        #expect(plan.prompt == nil)
    }

    @Test func freshActiveSessionNeedsNoPrompt() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 10 * 60)
        let plan = planner.plan(openSessions: [s], at: clock.instant())
        #expect(plan.survivor == s)
        #expect(plan.updates.isEmpty)
        #expect(plan.prompt == nil)
    }

    @Test func appKilledThenReopenedRestoresTheSameSession() throws {
        // Termination is invisible to the data: the snapshot from the store is simply still active.
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 20 * 60)
        let plan = planner.plan(openSessions: [s], at: clock.instant())
        #expect(approx(plan.survivor?.openSegment?.duration(at: clock.now), 20 * 60))
    }

    @Test func rebootDoesNotLookLikeAClockChange() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 5 * 60)
        clock.reboot(downtime: 90)
        let plan = planner.plan(openSessions: [s], at: clock.instant())
        #expect(plan.prompt == nil)
        #expect(plan.updates.isEmpty)
        #expect(approx(plan.survivor?.feedingDuration(at: clock.now), 5 * 60 + 90))
    }

    @Test func duplicatesKeepTheNewestAndCloseTheRestForReview() throws {
        let clock = TestClock()
        let older = try started(.left, clock: clock)
        clock.advance(by: 600)
        let newer = try started(.right, clock: clock)
        clock.advance(by: 300)
        let plan = planner.plan(openSessions: [older, newer], at: clock.instant())
        #expect(plan.survivor?.id == newer.id)
        #expect(plan.updates.count == 1)
        let closed = try #require(plan.updates.first)
        #expect(closed.id == older.id)
        #expect(closed.status == .completed)
        #expect(closed.needsReview)
        #expect(closed.source == .recovered)
        #expect(closed.endedAt == newer.startedAt)
        #expect(closed.revision == older.revision + 1)
        #expect(SessionValidator.isValid(closed, now: clock.now))
    }

    @Test func wallClockMovedForwardWithinTheSameBootIsDetected() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 10 * 60)
        clock.jumpWall(by: 3600)
        let plan = planner.plan(openSessions: [s], at: clock.instant())
        let prompt = try #require(plan.prompt)
        #expect(prompt.reason == .clockChanged)
        #expect(prompt.correctedStart == clock.now.addingTimeInterval(-10 * 60))
        #expect(plan.survivor?.needsReview == true)
        #expect(plan.updates.map(\.id) == [s.id])
        #expect(prompt.session.needsReview)
    }

    @Test func wallClockMovedBackwardsWithinTheSameBootIsDetected() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 5 * 60)
        clock.jumpWall(by: -3600)
        let plan = planner.plan(openSessions: [s], at: clock.instant())
        #expect(plan.prompt?.reason == .clockChanged)
        #expect(plan.prompt?.correctedStart == clock.now.addingTimeInterval(-5 * 60))
    }

    @Test func smallDriftIsIgnored() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 600)
        clock.jumpWall(by: 20)
        #expect(planner.plan(openSessions: [s], at: clock.instant()).prompt == nil)
    }

    @Test func futureStartAfterARebootIsFlagged() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.reboot()
        clock.jumpWall(by: -2 * 3600)
        let plan = planner.plan(openSessions: [s], at: clock.instant())
        #expect(plan.prompt?.reason == .futureStart)
        #expect(plan.prompt?.correctedStart == clock.now)
        #expect(plan.survivor?.needsReview == true)
    }

    @Test func alreadyFlaggedSessionIsNotSavedAgain() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 60)
        clock.jumpWall(by: 3600)
        let first = planner.plan(openSessions: [s], at: clock.instant())
        let second = planner.plan(openSessions: [first.survivor!], at: clock.instant())
        #expect(second.updates.isEmpty)
        #expect(second.prompt?.reason == .clockChanged)
    }

    @Test func longRunningSegmentAsksStillFeedingWithAPlausibleEnd() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 3 * 3600)
        let plan = planner.plan(openSessions: [s], at: clock.instant(), typicalSegmentDuration: 11 * 60)
        let prompt = try #require(plan.prompt)
        #expect(prompt.reason == .longRunning)
        #expect(prompt.suggestedEnd == s.startedAt.addingTimeInterval(11 * 60))
        #expect(plan.updates.isEmpty)
    }

    @Test func suggestedEndFallsBackToDefaultAndNeverExceedsNow() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 50 * 60)
        let plan = RecoveryPlanner(policy: RecoveryPolicy(defaultSegmentEstimate: 60 * 60)).plan(openSessions: [s], at: clock.instant())
        #expect(plan.prompt?.suggestedEnd == clock.now)
        let plan2 = planner.plan(openSessions: [s], at: clock.instant())
        #expect(plan2.prompt?.suggestedEnd == s.startedAt.addingTimeInterval(15 * 60))
    }

    @Test func thresholdIsCappedByTheHardLimit() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 3 * 3600 + 1)
        let lenient = RecoveryPlanner(policy: RecoveryPolicy(stillFeedingThreshold: 10 * 3600))
        #expect(lenient.plan(openSessions: [s], at: clock.instant()).prompt?.reason == .longRunning)
    }

    @Test func forgottenPausedSessionSuggestsEndingWhenItWasPaused() throws {
        let clock = TestClock()
        var s = try started(clock: clock)
        clock.advance(by: 600)
        s = try engine.apply(.pause, to: s, at: clock.instant()).snapshot
        let pausedAt = clock.now
        clock.advance(by: 2 * 3600)
        let plan = planner.plan(openSessions: [s], at: clock.instant())
        #expect(plan.prompt?.reason == .longRunning)
        #expect(plan.prompt?.suggestedEnd == pausedAt)
    }

    @Test func keepGoingRestartsTheCountAndSilencesClockIssues() throws {
        let clock = TestClock()
        let s = try started(clock: clock)
        clock.advance(by: 60 * 60)
        let ack = [s.id: clock.now]
        clock.advance(by: 10 * 60)
        #expect(planner.plan(openSessions: [s], at: clock.instant(), acknowledged: ack).prompt == nil)
        clock.advance(by: 40 * 60)
        #expect(planner.plan(openSessions: [s], at: clock.instant(), acknowledged: ack).prompt?.reason == .longRunning)

        clock.jumpWall(by: 3600)
        let ack2 = [s.id: clock.now]
        #expect(planner.plan(openSessions: [s], at: clock.instant(), acknowledged: ack2).prompt == nil)
    }

    @Test func acknowledgementStoredOnTheSessionIsHonoured() throws {
        let clock = TestClock()
        var s = try started(clock: clock)
        clock.advance(by: 60 * 60)
        s.recoveryAcknowledgedAt = clock.now
        clock.advance(by: 10 * 60)
        #expect(planner.plan(openSessions: [s], at: clock.instant()).prompt == nil)
    }

    @Test func typicalSegmentDurationIsTheMedianOfRealSegments() {
        let t0 = Date(timeIntervalSince1970: 0)
        func session(_ lengths: [TimeInterval]) -> SessionSnapshot {
            var start = t0
            let segs = lengths.map { len -> Segment in
                defer { start += len }
                return Segment(side: .left, start: start, end: start + len)
            }
            return SessionSnapshot(status: .completed, segments: segs, startedAt: t0, endedAt: start)
        }
        #expect(RecoveryPlanner.typicalSegmentDuration(from: []) == nil)
        #expect(RecoveryPlanner.typicalSegmentDuration(from: [session([600, 5, 900]), session([300])]) == 600)
        #expect(RecoveryPlanner.typicalSegmentDuration(from: [session([600, 900])]) == 750)
    }
}
