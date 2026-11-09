import Foundation
import NewbeeKit
import Testing
@testable import Newbee

/// A clock the tests move by hand.
@MainActor
final class ManualNow {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
@Suite("Timer screen display")
struct BreastfeedingTimerDisplayTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func notStartedSuggestsOppositeOfLastSide() {
        let last = PreviewSessionController.completedFixture(endingBefore: t0) // ended on the right
        let d = BreastfeedingTimerDisplay(session: nil, lastCompleted: last, suggestedSide: .left, now: t0)
        #expect(d.phase == .notStarted)
        #expect(d.suggestedSide == .left)
        #expect(d.lastFeedSide == .right)
        #expect(d.mode(for: .left) == .start(suggested: true))
        #expect(d.mode(for: .right) == .start(suggested: false))
    }

    @Test func activeShowsPerSideAndTotalFromTimestamps() {
        let switchAt = t0.addingTimeInterval(12 * 60)
        let s = SessionSnapshot(
            status: .active,
            segments: [Segment(side: .left, start: t0, end: switchAt), Segment(side: .right, start: switchAt)],
            startedAt: t0
        )
        let d = BreastfeedingTimerDisplay(session: s, lastCompleted: nil, suggestedSide: .left, now: switchAt.addingTimeInterval(9 * 60))
        #expect(d.phase == .active(.right))
        #expect(d.left == 12 * 60)
        #expect(d.right == 9 * 60)
        #expect(d.total == 21 * 60)
        #expect(d.suggestedSide == nil)
        #expect(d.mode(for: .right) == .active)
        #expect(d.mode(for: .left) == .switchTo)
    }

    @Test func pausedFreezesTotalsAndOffersResumeOnBothSides() {
        let s = SessionSnapshot(
            status: .paused,
            segments: [Segment(side: .left, start: t0, end: t0.addingTimeInterval(300))],
            startedAt: t0
        )
        let d = BreastfeedingTimerDisplay(session: s, lastCompleted: nil, suggestedSide: .right, now: t0.addingTimeInterval(3_600))
        #expect(d.isPaused)
        #expect(d.total == 300)
        #expect(d.mode(for: .left) == .resumeHere(wasLast: true))
        #expect(d.mode(for: .right) == .resumeHere(wasLast: false))
    }
}

@MainActor
@Suite("Timer screen actions")
struct FeedingSessionUIModelTests {
    let clock = ManualNow()
    let controller: PreviewSessionController
    let model: FeedingSessionUIModel

    init() {
        let clock = clock
        controller = PreviewSessionController(now: { clock.date })
        model = FeedingSessionUIModel(controller: controller)
    }

    /// The spec example: start left, switch after 12 min, end after 9 more.
    @Test func startSwitchEndRecordsTheSpecExample() throws {
        model.tapSide(.left)
        clock.advance(12 * 60)
        model.tapSide(.right)
        clock.advance(9 * 60)
        model.endSession()

        let done = try #require(controller.lastCompletedSession)
        let end = try #require(done.endedAt)
        #expect(done.duration(on: .left, at: end) == 12 * 60)
        #expect(done.duration(on: .right, at: end) == 9 * 60)
        #expect(model.completedSummary?.id == done.id)
        #expect(model.toast != nil)
        #expect(controller.activeSession == nil)
    }

    @Test func tappingTheRunningSideDoesNothing() {
        model.tapSide(.left)
        model.tapSide(.left)
        model.tapSide(.left)
        #expect(controller.log == ["start(left)"])
        #expect(controller.activeSession?.segments.count == 1)
    }

    @Test func tappingASideWhilePausedResumesOnThatSide() {
        model.tapSide(.left)
        clock.advance(60)
        model.togglePause()
        #expect(controller.activeSession?.status == .paused)
        clock.advance(60)
        model.tapSide(.right)
        #expect(controller.activeSession?.status == .active)
        #expect(controller.activeSession?.openSegment?.side == .right)
    }

    @Test func pauseThenResumeContinuesOnTheSameSide() {
        model.tapSide(.right)
        model.togglePause()
        model.togglePause()
        #expect(controller.activeSession?.status == .active)
        #expect(controller.activeSession?.openSegment?.side == .right)
    }

    @Test func undoAfterEndReopensTheSession() {
        model.tapSide(.left)
        clock.advance(300)
        model.endSession()
        #expect(controller.activeSession == nil)
        model.undo()
        #expect(controller.activeSession?.status == .active)
        #expect(model.toast == nil)
        #expect(model.completedSummary == nil)
    }

    @Test func discardHidesTheTimerAndCanBeUndone() {
        model.openTimer()
        model.tapSide(.left)
        model.discardSession()
        #expect(controller.activeSession == nil)
        #expect(model.isTimerPresented == false)
        model.undo()
        #expect(controller.activeSession != nil)
    }

    @Test func expiredToastNoLongerUndoes() throws {
        model.tapSide(.left)
        model.endSession()
        let id = try #require(model.toast?.id)
        model.dismissToast(id: id)
        model.undo()
        #expect(controller.activeSession == nil)
    }

    @Test func rejectedCommandWarnsWithoutCrashing() {
        // No session: pausing through the controller directly fails; the model reports it.
        model.recoveryEnd(at: nil)
        #expect(model.errorMessage != nil)
        #expect(model.feedback?.kind == .warning)
    }

    @Test func recoveryEndAtUsesTheChosenTime() throws {
        model.tapSide(.left)
        let started = clock.date
        clock.advance(3 * 3600)
        model.recoveryEnd(at: started.addingTimeInterval(25 * 60))
        let done = try #require(controller.lastCompletedSession)
        #expect(done.endedAt == started.addingTimeInterval(25 * 60))
        #expect(done.feedingDuration(at: clock.date) == 25 * 60)
    }
}

@Suite("Duration text")
struct DurationTextTests {
    @Test func clockFormat() {
        #expect(DurationText.clock(0) == "0:00")
        #expect(DurationText.clock(7.9) == "0:07")
        #expect(DurationText.clock(725) == "12:05")
        #expect(DurationText.clock(3_723) == "1:02:03")
        #expect(DurationText.clock(-5) == "0:00")
    }

    @Test func shortFormatShowsZeroForAnUnusedSide() {
        #expect(DurationText.short(0) == "0 min")
        #expect(DurationText.short(-3) == "0 min")
        #expect(DurationText.short(30) == "<1 min")
        #expect(DurationText.short(21 * 60) == "21 min")
        #expect(DurationText.short(65 * 60) == "1 h 5 min")
    }

    /// `Int(_:)` traps on NaN, infinity and values past `Int.max`, so a bad duration must never
    /// reach it: it reads as zero (or the cap) instead of crashing the screen that shows it.
    @MainActor
    @Test(arguments: [Double.nan, .infinity, -.infinity, -.greatestFiniteMagnitude])
    func unusableDurationsReadAsZero(_ value: Double) {
        #expect(DurationText.clock(value) == "0:00")
        #expect(DurationText.short(value) == "0 min")
        #expect(DurationText.spoken(value) == "0 minutes")
        #expect(DashboardView.compactAgo(value) == "just now")
    }

    @MainActor
    @Test func absurdlyLongDurationsAreCappedInsteadOfCrashing() {
        let huge = Double.greatestFiniteMagnitude
        #expect(DurationText.clock(huge) == DurationText.clock(DurationText.longest))
        #expect(DurationText.short(huge) == DurationText.short(DurationText.longest))
        #expect(!DurationText.spoken(huge).isEmpty)
        #expect(DashboardView.compactAgo(huge) == DashboardView.compactAgo(DurationText.longest))
    }

    @Test func calendarSidesLeaveOutAnUnusedSide() {
        #expect(FeedText.usedSides(left: 20 * 60, right: 0) == "L 20 min")
        #expect(FeedText.usedSides(left: 0, right: 9 * 60) == "R 9 min")
        #expect(FeedText.usedSides(left: 12 * 60, right: 9 * 60) == "L 12 min · R 9 min")
    }
}
