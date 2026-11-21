import Foundation
import Testing
@testable import NewbeeKit

private let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

private func ny(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func approx(_ actual: Double, _ expected: Double) -> Bool { abs(actual - expected) < 1e-9 }

@Suite("Calendar week view layout")
struct DayTimelineLayoutTests {
    @Test func positionsFollowTheClockOnAnOrdinaryDay() {
        #expect(DayTimelineLayout.position(of: ny(11, 7, 0), onDay: ny(11, 7, 0), calendar: newYork) == 0)
        #expect(approx(DayTimelineLayout.position(of: ny(11, 7, 6), onDay: ny(11, 7, 0), calendar: newYork), 0.25))
        #expect(approx(DayTimelineLayout.position(of: ny(11, 7, 18), onDay: ny(11, 7, 0), calendar: newYork), 0.75))
        // Before the day and from the next midnight on, it pins to the edges.
        #expect(DayTimelineLayout.position(of: ny(11, 6, 23), onDay: ny(11, 7, 0), calendar: newYork) == 0)
        #expect(DayTimelineLayout.position(of: ny(11, 8, 0), onDay: ny(11, 7, 0), calendar: newYork) == 1)
    }

    @Test func lateFeedsOnThe25HourDayStayInsideTheColumn() {
        // 24 h 30 min after midnight, but the clock reads 23:30.
        let late = ny(11, 1, 23, 30)
        #expect(approx(DayTimelineLayout.position(of: late, onDay: ny(11, 1, 0), calendar: newYork), 23.5 / 24))
        let span = DayTimelineLayout.span(from: late, to: late.addingTimeInterval(20 * 60), onDay: ny(11, 1, 0), calendar: newYork)
        #expect(approx(span.top, 23.5 / 24))
        #expect(approx(span.height, 20.0 / 1_440))
        #expect(span.top + span.height <= 1)
    }

    @Test func feedsAfterSpringForwardSitAtTheirClockTime() {
        // Only 2 h 30 min after midnight, but the clock reads 03:30.
        let span = DayTimelineLayout.span(from: ny(3, 8, 3, 30), to: ny(3, 8, 3, 50), onDay: ny(3, 8, 0), calendar: newYork)
        #expect(approx(span.top, 3.5 / 24))
        #expect(approx(span.height, 20.0 / 1_440))
        // A feed across the jump: 01:50 EST to 03:10 EDT is drawn from 01:50 to 03:10 on the axis.
        let across = DayTimelineLayout.span(from: ny(3, 8, 1, 50), to: ny(3, 8, 3, 10), onDay: ny(3, 8, 0), calendar: newYork)
        #expect(approx(across.top, (1 + 50.0 / 60) / 24))
        #expect(approx(across.top + across.height, (3 + 10.0 / 60) / 24))
    }

    @Test func aFeedDuringTheRepeatedHourKeepsItsRealLength() {
        // 01:50 EDT to 01:10 EST: the clock goes backwards, the feed lasted 20 minutes.
        let start = ny(11, 1, 1, 50)
        let end = start.addingTimeInterval(20 * 60)
        #expect(newYork.component(.hour, from: end) == 1 && newYork.component(.minute, from: end) == 10)
        let span = DayTimelineLayout.span(from: start, to: end, onDay: ny(11, 1, 0), calendar: newYork)
        #expect(approx(span.top, (1 + 50.0 / 60) / 24))
        #expect(approx(span.height, 20.0 / 1_440))
    }

    @Test func aFeedIntoTheNextDayIsClippedAtMidnight() {
        let span = DayTimelineLayout.span(from: ny(11, 7, 23, 50), to: ny(11, 8, 0, 20), onDay: ny(11, 7, 0), calendar: newYork)
        #expect(approx(span.top + span.height, 1))
        // An instant entry (a bottle) has no height; the view gives it a minimum.
        let bottle = DayTimelineLayout.span(from: ny(11, 7, 9), to: ny(11, 7, 9), onDay: ny(11, 7, 0), calendar: newYork)
        #expect(bottle.height == 0)
        // An end before the start never draws upwards.
        let backwards = DayTimelineLayout.span(from: ny(11, 7, 9), to: ny(11, 7, 8), onDay: ny(11, 7, 0), calendar: newYork)
        #expect(backwards.height == 0)
    }
}

@Suite("Day view lanes")
struct DayTimelineLanesTests {
    private func span(_ startHour: Double, _ minutes: Double) -> DayTimelineLayout.Span {
        DayTimelineLayout.Span(top: startHour / 24, height: minutes / 1_440)
    }

    @Test func separateBlocksTakeTheFullWidth() {
        let lanes = DayTimelineLayout.lanes(for: [span(9, 20), span(12, 15), span(15, 30)])
        #expect(lanes.allSatisfy { $0 == .init(index: 0, count: 1) })
    }

    @Test func aPumpDuringAFeedSitsBesideIt() {
        // Feed 9:00–9:30, pump 9:10–9:25.
        let lanes = DayTimelineLayout.lanes(for: [span(9, 30), span(9 + 10.0 / 60, 15)])
        #expect(lanes == [.init(index: 0, count: 2), .init(index: 1, count: 2)])
    }

    @Test func blocksThatTouchShareALane() {
        // 9:00–9:30, then 9:30–9:45.
        let lanes = DayTimelineLayout.lanes(for: [span(9, 30), span(9.5, 15)])
        #expect(lanes == [.init(index: 0, count: 1), .init(index: 0, count: 1)])
    }

    @Test func aFreedLaneIsReusedAndTheRunKeepsItsWidth() {
        // A 9:00–10:00, B 9:10–9:20, C 9:30–9:40: C fits back in B's lane, all three halves.
        let lanes = DayTimelineLayout.lanes(for: [span(9, 60), span(9 + 10.0 / 60, 10), span(9.5, 10)])
        #expect(lanes == [.init(index: 0, count: 2), .init(index: 1, count: 2), .init(index: 1, count: 2)])
    }

    @Test func aBottleGetsItsOwnLaneOnceDrawnAtItsMinimumHeight() {
        // A bottle (no duration) at 9:00 and a feed at 9:10. Drawn at least 20 minutes tall, the
        // bottle would cover the feed's start.
        let spans = [span(9, 0), span(9 + 10.0 / 60, 15)]
        #expect(DayTimelineLayout.lanes(for: spans) == [.init(index: 0, count: 1), .init(index: 0, count: 1)])
        let lanes = DayTimelineLayout.lanes(for: spans, minimumHeight: 20.0 / 1_440)
        #expect(lanes == [.init(index: 0, count: 2), .init(index: 1, count: 2)])
    }

    @Test func lanesComeBackInTheOrderGiven() {
        let lanes = DayTimelineLayout.lanes(for: [span(9 + 10.0 / 60, 15), span(9, 30)])
        #expect(lanes == [.init(index: 1, count: 2), .init(index: 0, count: 2)])
    }
}
