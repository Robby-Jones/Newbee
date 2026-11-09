import Foundation
import Testing
@testable import NewbeeKit

/// A feed that is paused (not running) when the clock moves backwards, for example after a
/// restart with a wrong clock. Its pause time then lies in the future, and recovery must offer
/// the same "Fix start time" path a running feed gets.
@MainActor
@Suite("Clock change while paused")
struct PausedClockChangeTests {
    let clock = TestClock()
    let engine = SessionEngine()

    /// Left for 10 minutes, paused, then 5 minutes later the phone restarts an hour behind.
    func pausedThenClockBack() throws -> (InMemoryFeedingRepository, FeedingSessionManager, RecoveryCoordinator) {
        let repository = InMemoryFeedingRepository()
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        try manager.start(side: .left)
        clock.advance(by: 10 * 60)
        try manager.pause()
        clock.advance(by: 5 * 60)
        clock.reboot()
        clock.jumpWall(by: -3_600)
        return (repository, manager, RecoveryCoordinator(manager: manager))
    }

    @Test func plannerFlagsAPauseTimeInTheFuture() throws {
        let start = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 10 * 60)
        let paused = try engine.apply(.pause, to: start, at: clock.instant()).snapshot
        clock.reboot()
        clock.jumpWall(by: -3_600)
        let plan = RecoveryPlanner().plan(openSessions: [paused], at: clock.instant())
        #expect(plan.prompt?.reason == .futureStart)
        #expect(plan.prompt?.correctedStart == clock.now)
        #expect(plan.survivor?.needsReview == true)
        #expect(plan.updates.count == 1)
    }

    @Test func endingIsRefusedUntilTheTimesAreFixed() async throws {
        let (_, manager, recovery) = try pausedThenClockBack()
        await recovery.reconcile()
        #expect(manager.recoveryPrompt?.reason == .futureStart)
        // Every stored time is in the future, so there is no honest end time to pick.
        #expect(throws: (any Error).self) { try manager.end() }
        #expect(manager.activeSession?.status == .paused)
    }

    @Test func fixStartTimeMovesThePauseToNowAndKeepsTheFeedLength() async throws {
        let (repository, manager, recovery) = try pausedThenClockBack()
        await recovery.reconcile()
        let prompt = try #require(manager.recoveryPrompt)

        try manager.adjustStart(to: try #require(prompt.correctedStart))
        let fixed = try #require(manager.activeSession)
        #expect(fixed.status == .paused)
        #expect(fixed.segments.last?.end == clock.now)
        #expect(approx(fixed.duration(on: .left, at: clock.now), 10 * 60))
        #expect(try repository.activeSession() == fixed)

        // Resume and end normally: the feed is valid and only the real time counts.
        clock.advance(by: 60)
        try manager.resume()
        clock.advance(by: 3 * 60)
        let ended = try manager.end()
        #expect(ended.id == fixed.id)
        let done = try #require(manager.lastCompletedSession)
        #expect(SessionValidator.isValid(done, now: clock.now))
        #expect(approx(done.feedingDuration(at: clock.now), 13 * 60))

        // A relaunch finds nothing left to recover.
        await recovery.reconcile()
        #expect(manager.recoveryPrompt == nil)
    }

    @Test func endingAtThePauseAfterTheFixUsesThePauseTime() async throws {
        let (_, manager, recovery) = try pausedThenClockBack()
        await recovery.reconcile()
        try manager.adjustStart(to: try #require(manager.recoveryPrompt?.correctedStart))
        let pausedAt = clock.now
        clock.advance(by: 120)
        try manager.end()
        #expect(manager.lastCompletedSession?.endedAt == pausedAt)
    }

    @Test func fixStartTimeWithNoFeedThrows() {
        let manager = FeedingSessionManager(repository: InMemoryFeedingRepository(), clock: clock)
        #expect(throws: SessionEngineError.noActiveSession) { try manager.adjustStart(to: clock.now) }
    }

    @Test func savingAnEditToAFeedDeletedMeanwhileIsReported() throws {
        let manager = FeedingSessionManager(repository: InMemoryFeedingRepository(), clock: clock)
        let start = clock.now.addingTimeInterval(-600)
        let gone = SessionSnapshot(
            status: .completed,
            segments: [Segment(side: .left, start: start, end: clock.now)],
            startedAt: start,
            endedAt: clock.now
        )
        #expect(throws: FeedingSessionError.sessionNotFound(gone.id)) { try manager.saveEdit(gone) }
        #expect(manager.lastCompletedSession == nil)
    }
}
