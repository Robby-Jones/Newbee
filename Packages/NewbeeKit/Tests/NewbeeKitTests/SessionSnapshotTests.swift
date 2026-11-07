import Foundation
import Testing
@testable import NewbeeKit

@Suite("SessionSnapshot durations")
struct SessionSnapshotTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// The guide's example: left 12 min from 2:15, right 9 min, end 2:36.
    @Test func specExampleLeftTwelveRightNine() {
        let switchAt = t0.addingTimeInterval(12 * 60)
        let end = switchAt.addingTimeInterval(9 * 60)
        let s = SessionSnapshot(
            status: .completed,
            segments: [
                Segment(side: .left, start: t0, end: switchAt),
                Segment(side: .right, start: switchAt, end: end),
            ],
            startedAt: t0,
            endedAt: end
        )
        #expect(s.duration(on: .left, at: end) == 12 * 60)
        #expect(s.duration(on: .right, at: end) == 9 * 60)
        #expect(s.feedingDuration(at: end) == 21 * 60)
        #expect(s.span(at: end) == 21 * 60)
        #expect(s.startingSide == .left)
        #expect(s.lastSide == .right)
        #expect(s.openSegment == nil)
    }

    @Test func pausesAreExcludedFromFeedingTimeButIncludedInSpan() {
        let s = SessionSnapshot(
            status: .completed,
            segments: [
                Segment(side: .left, start: t0, end: t0.addingTimeInterval(300)),
                Segment(side: .left, start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(900)),
            ],
            startedAt: t0,
            endedAt: t0.addingTimeInterval(900)
        )
        #expect(s.feedingDuration(at: t0.addingTimeInterval(900)) == 600)
        #expect(s.span(at: t0.addingTimeInterval(900)) == 900)
    }

    @Test func openSegmentGrowsWithNowAndClosedDurationDoesNot() {
        let s = SessionSnapshot(
            status: .active,
            segments: [
                Segment(side: .left, start: t0, end: t0.addingTimeInterval(120)),
                Segment(side: .right, start: t0.addingTimeInterval(120)),
            ],
            startedAt: t0
        )
        let now = t0.addingTimeInterval(420)
        #expect(s.openSegment?.side == .right)
        #expect(s.duration(on: .right, at: now) == 300)
        #expect(s.closedDuration(on: .right) == 0)
        #expect(s.closedDuration(on: .left) == 120)
        #expect(s.feedingDuration(at: now) == 420)
    }

    @Test func clockGoingBackwardsNeverProducesNegativeDurations() {
        let seg = Segment(side: .left, start: t0)
        #expect(seg.duration(at: t0.addingTimeInterval(-3600)) == 0)
    }

    @Test func sideOpposite() {
        #expect(Side.left.opposite == .right)
        #expect(Side.right.opposite == .left)
    }

    @Test func persistedRawValuesAreStable() {
        #expect(Side.allCases.map(\.rawValue) == ["left", "right"])
        #expect(SessionStatus.allCases.map(\.rawValue) == ["active", "paused", "completed"])
        #expect(FeedingKind.allCases.map(\.rawValue) == ["breast", "bottle", "pump", "combo"])
        #expect(BottleContents.allCases.map(\.rawValue) == ["breastMilk", "formula", "other"])
    }
}

@Suite("Clocks and units")
struct ClockAndUnitTests {
    @Test func testClockAdvanceMovesBothClocks() {
        let c = TestClock()
        let a = c.instant()
        c.advance(by: 90)
        let b = c.instant()
        #expect(b.wall.timeIntervalSince(a.wall) == 90)
        #expect(b.monotonic! - a.monotonic! == 90)
        #expect(a.bootID == b.bootID)
    }

    @Test func testClockWallJumpLeavesMonotonicAlone() {
        let c = TestClock()
        let a = c.instant()
        c.jumpWall(by: 3600)
        let b = c.instant()
        #expect(b.wall.timeIntervalSince(a.wall) == 3600)
        #expect(b.monotonic == a.monotonic)
    }

    @Test func testClockRebootChangesBootID() {
        let c = TestClock()
        let a = c.instant()
        c.reboot()
        #expect(c.instant().bootID != a.bootID)
    }

    @Test func systemClockProvidesMonotonicAndBootID() {
        let i = SystemClock().instant()
        #expect(i.monotonic != nil)
        #expect(i.bootID != nil)
    }

    @Test func ounceConversionRoundTrips() {
        let ml = VolumeUnit.fluidOunces.toMilliliters(4)
        #expect(abs(ml - 118.29411825) < 0.0001)
        #expect(abs(VolumeUnit.fluidOunces.fromMilliliters(ml) - 4) < 0.000001)
        #expect(VolumeUnit.milliliters.toMilliliters(90) == 90)
    }
}
