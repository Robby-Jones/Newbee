import Foundation
import Testing
@testable import NewbeeKit

/// Every row of the state table in docs/TIMER_ENGINE.md §3, plus time edge cases (§6).
@Suite("SessionEngine")
struct SessionEngineTests {
    let engine = SessionEngine(timeZone: TimeZone(identifier: "America/New_York")!)

    /// Applies a command, asserting it is accepted.
    func run(_ command: SessionCommand, _ state: SessionSnapshot?, _ clock: TestClock) throws -> SessionSnapshot {
        try engine.apply(command, to: state, at: clock.instant()).snapshot
    }

    // MARK: Not started

    @Test func startCreatesActiveSessionWithOneOpenSegment() throws {
        let clock = TestClock()
        let t = try engine.apply(.start(.left), to: nil, at: clock.instant())
        let s = t.snapshot
        #expect(s.status == .active)
        #expect(s.segments.count == 1)
        #expect(s.openSegment?.side == .left)
        #expect(s.startedAt == clock.now)
        #expect(s.revision == 1)
        #expect(s.timeZoneID == "America/New_York")
        #expect(s.source == .timer)
        #expect(s.openSegment?.startMonotonic == clock.instant().monotonic)
        #expect(s.openSegment?.startBootID == clock.instant().bootID)
        #expect(t.effects == [.persist, .updateActivity, .rescheduleReminders])
        #expect(SessionValidator.isValid(s, now: clock.now))
    }

    @Test(arguments: [SessionCommand.switchTo(.left), .pause, .resume, .end, .endAt(Date()), .shiftTimestamps(by: 60)])
    func commandsWithoutASessionAreRejected(command: SessionCommand) {
        #expect(throws: SessionEngineError.noActiveSession) {
            try engine.apply(command, to: nil, at: TestClock().instant())
        }
    }

    @Test func startWhileActiveOrPausedIsRejectedWithTheExistingID() throws {
        let clock = TestClock()
        let active = try run(.start(.left), nil, clock)
        #expect(throws: SessionEngineError.alreadyActive(active.id)) {
            try engine.apply(.start(.right), to: active, at: clock.instant())
        }
        clock.advance(by: 60)
        let paused = try run(.pause, active, clock)
        #expect(throws: SessionEngineError.alreadyActive(active.id)) {
            try engine.apply(.start(.left), to: paused, at: clock.instant())
        }
    }

    // MARK: Active

    @Test func switchClosesSegmentAndOpensOtherSideAtTheSameInstant() throws {
        let clock = TestClock()
        let s0 = try run(.start(.left), nil, clock)
        clock.advance(by: 12 * 60)
        let t = try engine.apply(.switchTo(.right), to: s0, at: clock.instant())
        let s1 = t.snapshot
        #expect(s1.segments.count == 2)
        #expect(s1.segments[0].end == clock.now)
        #expect(s1.segments[1].start == clock.now)
        #expect(s1.segments[1].side == .right)
        #expect(s1.openSegment?.id == s1.segments[1].id)
        #expect(s1.revision == 2)
        #expect(t.effects == [.persist, .updateActivity, .rescheduleReminders])
    }

    @Test func switchToCurrentSideIsANoOp() throws {
        let clock = TestClock()
        let s0 = try run(.start(.left), nil, clock)
        clock.advance(by: 30)
        let t = try engine.apply(.switchTo(.left), to: s0, at: clock.instant())
        #expect(t.isNoOp)
        #expect(t.snapshot == s0)
    }

    @Test func pauseClosesTheRunningSegment() throws {
        let clock = TestClock()
        let s0 = try run(.start(.left), nil, clock)
        clock.advance(by: 300)
        let s1 = try run(.pause, s0, clock)
        #expect(s1.status == .paused)
        #expect(s1.openSegment == nil)
        #expect(s1.segments[0].end == clock.now)
        #expect(s1.revision == 2)
        #expect(SessionValidator.isValid(s1, now: clock.now))
    }

    @Test func resumeWhileActiveIsANoOp() throws {
        let clock = TestClock()
        let s0 = try run(.start(.left), nil, clock)
        #expect(try engine.apply(.resume, to: s0, at: clock.instant()).isNoOp)
    }

    @Test func endWhileActiveClosesSegmentAndCompletes() throws {
        let clock = TestClock()
        let s0 = try run(.start(.right), nil, clock)
        clock.advance(by: 600)
        let t = try engine.apply(.end, to: s0, at: clock.instant())
        #expect(t.snapshot.status == .completed)
        #expect(t.snapshot.endedAt == clock.now)
        #expect(t.snapshot.segments[0].end == clock.now)
        #expect(t.effects == [.persist, .endActivity, .rescheduleReminders])
        #expect(SessionValidator.isValid(t.snapshot, now: clock.now))
    }

    // MARK: Paused

    @Test func pauseWhilePausedIsANoOp() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 60)
        s = try run(.pause, s, clock)
        clock.advance(by: 60)
        #expect(try engine.apply(.pause, to: s, at: clock.instant()).isNoOp)
    }

    @Test func resumeOpensSegmentOnLastSide() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 60)
        s = try run(.switchTo(.right), s, clock)
        clock.advance(by: 60)
        s = try run(.pause, s, clock)
        clock.advance(by: 120)
        s = try run(.resume, s, clock)
        #expect(s.status == .active)
        #expect(s.openSegment?.side == .right)
        #expect(s.openSegment?.start == clock.now)
        #expect(s.segments.count == 3)
        // The pause is a gap: excluded from feeding time, included in span.
        clock.advance(by: 60)
        #expect(approx(s.feedingDuration(at: clock.now), 180))
        #expect(s.span(at: clock.now) == 300)
    }

    @Test func switchWhilePausedResumesOnThatSide() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 60)
        s = try run(.pause, s, clock)
        clock.advance(by: 60)
        s = try run(.switchTo(.left), s, clock)
        #expect(s.status == .active)
        #expect(s.openSegment?.side == .left)
        #expect(s.segments.count == 2)
    }

    @Test func endWhilePausedUsesThePauseTimeAsEnd() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 300)
        s = try run(.pause, s, clock)
        let pausedAt = clock.now
        clock.advance(by: 3600)
        s = try run(.end, s, clock)
        #expect(s.status == .completed)
        #expect(s.endedAt == pausedAt)
    }

    // MARK: Completed

    @Test(arguments: [SessionCommand.start(.left), .switchTo(.right), .pause, .resume, .end, .endAt(Date())])
    func anyCommandAfterCompletionIsRejected(command: SessionCommand) throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 60)
        s = try run(.end, s, clock)
        #expect(throws: SessionEngineError.alreadyCompleted(s.id)) {
            try engine.apply(command, to: s, at: clock.instant())
        }
    }

    // MARK: Rapid taps

    @Test func rapidSwitchRetargetsTheSegmentInsteadOfStoringAZeroLengthOne() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 0.3)
        s = try run(.switchTo(.right), s, clock)
        #expect(s.segments.count == 1)
        #expect(s.openSegment?.side == .right)
        #expect(s.startedAt == s.segments[0].start)
    }

    @Test func switchBackWithinASecondReopensTheInterruptedSegment() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        let firstID = s.segments[0].id
        clock.advance(by: 300)
        s = try run(.switchTo(.right), s, clock)
        clock.advance(by: 0.4)
        s = try run(.switchTo(.left), s, clock)
        #expect(s.segments.count == 1)
        #expect(s.segments[0].id == firstID)
        #expect(s.openSegment?.side == .left)
        #expect(s.revision == 3)
    }

    @Test func fiveRapidSwitchesEndOnTheLastRequestedSideWithoutJunkSegments() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 120)
        for side in [Side.right, .left, .right, .left, .right] {
            s = try run(.switchTo(side), s, clock)
            clock.advance(by: 0.15)
        }
        #expect(s.openSegment?.side == .right)
        #expect(s.segments.map(\.side) == [.left, .right])
        #expect(SessionValidator.isValid(s, now: clock.now))
    }

    @Test func pauseImmediatelyAfterResumeDropsTheBlip() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 60)
        s = try run(.pause, s, clock)
        clock.advance(by: 60)
        s = try run(.resume, s, clock)
        clock.advance(by: 0.2)
        s = try run(.pause, s, clock)
        #expect(s.status == .paused)
        #expect(s.segments.count == 1)
    }

    @Test func pauseImmediatelyAfterStartKeepsTheOnlySegment() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 0.2)
        s = try run(.pause, s, clock)
        #expect(s.status == .paused)
        #expect(s.segments.count == 1)
        #expect(SessionValidator.isValid(s, now: clock.now))
    }

    // MARK: The spec example and multiple switches

    @Test func specExampleLeft12Right9() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 2, minute: 15))!
        let clock = TestClock(wall: start)
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 12 * 60)
        s = try run(.switchTo(.right), s, clock)
        clock.advance(by: 9 * 60)
        s = try run(.end, s, clock)

        #expect(s.startedAt == start)
        #expect(s.duration(on: .left, at: clock.now) == 12 * 60)
        #expect(s.duration(on: .right, at: clock.now) == 9 * 60)
        #expect(approx(s.feedingDuration(at: clock.now), 21 * 60))
        #expect(calendar.dateComponents([.hour, .minute], from: s.endedAt!) == DateComponents(hour: 2, minute: 36))
        #expect(s.segments.count == 2)
        #expect(s.revision == 3)
    }

    @Test func manySwitchesAccumulatePerSide() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 360)
        for side in [Side.right, .left, .right, .left] {
            s = try run(.switchTo(side), s, clock)
            clock.advance(by: 60)
        }
        s = try run(.end, s, clock)
        #expect(s.segments.count == 5)
        #expect(s.duration(on: .left, at: clock.now) == 360 + 60 + 60)
        #expect(s.duration(on: .right, at: clock.now) == 60 + 60)
        #expect(SessionValidator.isValid(s, now: clock.now))
    }

    // MARK: endAt and adjustments

    @Test func endAtClosesRunningSegmentAtTheChosenTimeAndMarksEstimate() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        let start = clock.now
        clock.advance(by: 3 * 3600)
        s = try run(.endAt(start.addingTimeInterval(20 * 60)), s, clock)
        #expect(s.status == .completed)
        #expect(s.endedAt == start.addingTimeInterval(20 * 60))
        #expect(approx(s.feedingDuration(at: clock.now), 20 * 60))
        #expect(s.source == .recovered)
    }

    @Test func endAtBeforeTheRunningSegmentOrInTheFutureIsRejected() throws {
        let clock = TestClock()
        let s = try run(.start(.left), nil, clock)
        clock.advance(by: 600)
        #expect(throws: SessionEngineError.invalidTime) {
            try engine.apply(.endAt(s.startedAt.addingTimeInterval(-1)), to: s, at: clock.instant())
        }
        #expect(throws: SessionEngineError.invalidTime) {
            try engine.apply(.endAt(clock.now.addingTimeInterval(3600)), to: s, at: clock.instant())
        }
    }

    @Test func shiftingMovesEveryTimestampAndKeepsLengths() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 600)
        s = try run(.switchTo(.right), s, clock)
        clock.advance(by: 300)
        let before = s
        s = try run(.shiftTimestamps(by: -120), s, clock)
        #expect(s.startedAt == before.startedAt.addingTimeInterval(-120))
        #expect(s.segments.map(\.start) == before.segments.map { $0.start.addingTimeInterval(-120) })
        #expect(approx(s.segments[0].duration(at: clock.now), 600))
        #expect(approx(s.duration(on: .right, at: clock.now), 420))
        #expect(s.revision == before.revision + 1)
        #expect(SessionValidator.isValid(s, now: clock.now))
    }

    @Test func shiftingIntoTheFutureIsRejected() throws {
        let clock = TestClock()
        let s = try run(.start(.left), nil, clock)
        clock.advance(by: 60)
        #expect(throws: SessionEngineError.invalidTime) {
            try engine.apply(.shiftTimestamps(by: 3600), to: s, at: clock.instant())
        }
        #expect(try engine.apply(.shiftTimestamps(by: 0), to: s, at: clock.instant()).isNoOp)
    }

    // MARK: Clock moved backwards (stored times in the future)

    /// L 9:00–9:55, R from 10:00; at 10:30 the clock is set back 2 h (now reads 8:30).
    func sessionAfterBackwardsClockChange(_ clock: TestClock) throws -> SessionSnapshot {
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 55 * 60)
        s = try run(.pause, s, clock)
        clock.advance(by: 5 * 60)
        s = try run(.switchTo(.right), s, clock)
        clock.advance(by: 30 * 60)
        clock.jumpWall(by: -2 * 3600)
        return s
    }

    @Test func endNowWithEverythingInTheFutureIsRefused() throws {
        let clock = TestClock()
        let s = try sessionAfterBackwardsClockChange(clock)
        #expect(SessionEngine.endTimeRange(for: s, now: clock.now) == nil)
        #expect(throws: SessionEngineError.invalidTime) { try engine.apply(.end, to: s, at: clock.instant()) }
    }

    @Test func endNowDropsOnlyTheFuturePartWhenSomeDataIsInThePast() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 20 * 60)
        s = try run(.switchTo(.right), s, clock)
        clock.advance(by: 5 * 60)
        clock.jumpWall(by: -10 * 60)   // now is 15 min after start; R "started" at 20 min
        let t = try engine.apply(.end, to: s, at: clock.instant())
        #expect(t.snapshot.status == .completed)
        #expect(t.snapshot.segments.map(\.side) == [.left])
        #expect(t.snapshot.endedAt == clock.now)
        #expect(SessionValidator.isValid(t.snapshot, now: clock.now))

        let range = try #require(SessionEngine.endTimeRange(for: s, now: clock.now))
        #expect(range.lowerBound == s.startedAt)
        let atTen = try run(.endAt(s.startedAt.addingTimeInterval(600)), s, clock)
        #expect(approx(atTen.feedingDuration(at: clock.now), 600))
        #expect(SessionValidator.isValid(atTen, now: clock.now))
    }

    @Test func endAtUsesTheSameRangeTheRecoveryPickerShows() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 600)
        s = try run(.switchTo(.right), s, clock)
        clock.advance(by: 3600)
        let range = try #require(SessionEngine.endTimeRange(for: s, now: clock.now))
        #expect(range.lowerBound == s.openSegment?.start)
        #expect(throws: SessionEngineError.invalidTime) {
            // Between the session start and the running segment: before what the engine accepts.
            try engine.apply(.endAt(s.startedAt.addingTimeInterval(300)), to: s, at: clock.instant())
        }
        #expect(try engine.apply(.endAt(range.lowerBound), to: s, at: clock.instant()).snapshot.status == .completed)
    }

    @Test func revisionIncrementsOnlyOnAcceptedChanges() throws {
        let clock = TestClock()
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 10)
        s = try run(.switchTo(.left), s, clock)  // no-op
        s = try run(.resume, s, clock)           // no-op
        #expect(s.revision == 1)
        s = try run(.pause, s, clock)
        s = try run(.pause, s, clock)            // no-op
        #expect(s.revision == 2)
    }

    // MARK: Time edge cases

    @Test func sessionCrossingMidnightKeepsExactDurations() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 23, minute: 50))!
        let clock = TestClock(wall: start)
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 15 * 60)
        s = try run(.switchTo(.right), s, clock)
        clock.advance(by: 10 * 60)
        s = try run(.end, s, clock)
        #expect(approx(s.feedingDuration(at: clock.now), 25 * 60))
        #expect(calendar.component(.day, from: s.startedAt) == 7)
        #expect(calendar.component(.day, from: s.endedAt!) == 8)
    }

    @Test func dstFallBackDoesNotDistortDuration() throws {
        // 2026-11-01 01:30 EDT, then clocks fall back at 02:00 EDT → 01:00 EST.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))!
        let clock = TestClock(wall: start)
        var s = try run(.start(.left), nil, clock)
        clock.advance(by: 40 * 60)
        s = try run(.end, s, clock)
        #expect(approx(s.feedingDuration(at: clock.now), 40 * 60))
    }

    @Test func wallClockJumpBackwardsNeverProducesNegativeOrFutureData() throws {
        let clock = TestClock()
        let s = try run(.start(.left), nil, clock)
        clock.jumpWall(by: -3600)
        #expect(s.segments[0].duration(at: clock.now) == 0)
        // Ending would store a future timestamp, so it's refused until the times are fixed.
        #expect(throws: SessionEngineError.invalidTime) { try engine.apply(.end, to: s, at: clock.instant()) }
        let fixed = try run(.shiftTimestamps(by: -3600), s, clock)
        let ended = try run(.end, fixed, clock)
        #expect(SessionValidator.isValid(ended, now: clock.now))
    }

    @Test func corruptActiveSessionWithoutOpenSegmentStillRecovers() throws {
        let clock = TestClock()
        let t0 = clock.now
        let corrupt = SessionSnapshot(
            status: .active,
            segments: [Segment(side: .left, start: t0, end: t0.addingTimeInterval(60))],
            startedAt: t0
        )
        clock.advance(by: 120)
        let resumed = try run(.resume, corrupt, clock)
        #expect(resumed.openSegment?.side == .left)
        #expect(SessionValidator.isValid(resumed, now: clock.now))
    }
}
