import Foundation
import Testing
@testable import NewbeeKit

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2 // Monday
    return calendar
}()

/// Saturday 2026-11-07 00:00 UTC.
private let midnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 7))!

private func at(_ hour: Double, day: Int = 0) -> Date { midnight.addingTimeInterval(Double(day) * 86_400 + hour * 3600) }

private func breast(_ start: Date, left: TimeInterval, right: TimeInterval, first: Side = .left, notes: String = "") -> FeedEntry {
    let last: Side = (first == .left ? right : left) > 0 ? first.opposite : first
    return FeedEntry(id: UUID(), start: start, end: start.addingTimeInterval(left + right),
                     details: .breast(left: left, right: right, firstSide: first, lastSide: last), notes: notes)
}

private func bottle(_ start: Date, ml: Double, unit: VolumeUnit = .milliliters) -> FeedEntry {
    FeedEntry(id: UUID(), start: start, end: start, details: .bottle(BottleSummary(contents: .formula, amountML: ml, enteredUnit: unit)), source: .manual)
}

@Suite("Tools")
struct ToolsTests {
    @Test func intervalBetweenFeedsBothWays() {
        let a = breast(at(2.25), left: 12 * 60, right: 9 * 60)
        let b = bottle(at(5.25), ml: 90)
        #expect(IntervalCalculator.interval(between: a, and: b, basis: .startToStart) == 3 * 3600)
        #expect(IntervalCalculator.interval(between: b, and: a, basis: .startToStart) == 3 * 3600)
        #expect(IntervalCalculator.interval(between: a, and: b, basis: .endToStart) == 3 * 3600 - 21 * 60)
        #expect(IntervalCalculator.since(a, at: at(3), basis: .endToStart) == 45 * 60 - 21 * 60)
        #expect(IntervalCalculator.since(a, at: at(1), basis: .startToStart) == 0)
    }

    @Test func sideTrackerSuggestsTheOppositeOfTheLastSide() {
        let entries = [
            breast(at(1), left: 600, right: 300, first: .left),   // ends right
            bottle(at(3), ml: 60),
            breast(at(5), left: 0, right: 900, first: .right),    // ends right
        ]
        let tracker = SideTracker(entries: entries)
        #expect(tracker.lastSide == .right)
        #expect(tracker.suggestedNextSide == .left)
        #expect(tracker.recentStartingSides == [.right, .left])
        #expect(tracker.recentLeft == 600)
        #expect(tracker.recentRight == 1200)
        #expect(tracker.leftShare == 600.0 / 1800.0)
        #expect(SideTracker(entries: []).suggestedNextSide == .left)
        #expect(SideTracker(entries: []).leftShare == nil)
    }

    @Test func quickStatsCoverTodayAndThisWeek() {
        // Week starts Monday 2026-11-02 (day -5).
        let entries = [
            breast(at(10, day: -6), left: 600, right: 0), // previous week
            breast(at(10, day: -5), left: 600, right: 0),
            bottle(at(12, day: -1), ml: 90),
            breast(at(3), left: 600, right: 600),
            bottle(at(6), ml: 120),
            bottle(at(20), ml: 60), // in the future at 08:00
        ]
        let stats = QuickStats(entries: entries, now: at(8), calendar: utc)
        #expect(stats.today.feedCount == 2)
        #expect(stats.today.bottleML == 120)
        #expect(stats.thisWeek.feedCount == 4)
        #expect(stats.averageFeedsPerDayThisWeek == 4.0 / 6.0)
    }
}

@Suite("CSV export")
struct FeedCSVTests {
    @Test func writesHeaderAndRowsOldestFirst() {
        let utcZone = TimeZone(identifier: "UTC")!
        let csv = FeedCSV.make([
            bottle(at(5.25), ml: 88.7, unit: .fluidOunces),
            breast(at(2.25), left: 12 * 60, right: 9 * 60, notes: "sleepy, \"latched\" well"),
        ], timeZone: utcZone)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == FeedCSV.header.joined(separator: ","))
        #expect(lines[1] == "2026-11-07 02:15,2026-11-07 02:36,2026-11-07T02:15:00Z,breast,21.0,12.0,9.0,left,right,,,,,timer,no,\"sleepy, \"\"latched\"\" well\"")
        #expect(lines[2] == "2026-11-07 05:15,2026-11-07 05:15,2026-11-07T05:15:00Z,bottle,,,,,,formula,89,3.0,oz,manual,no,")
        #expect(lines.last == "")
        #expect(lines.count == 4)
    }

    @Test func neutralisesFormulas() {
        #expect(FeedCSV.escape("=HYPERLINK(1)") == "'=HYPERLINK(1)")
        #expect(FeedCSV.escape("-12") == "-12")
        #expect(FeedCSV.escape("plain") == "plain")
    }

    @Test func namesTheFileByDate() {
        #expect(FeedCSV.fileName(at: at(8), timeZone: TimeZone(identifier: "UTC")!) == "Newbee feeds 2026-11-07.csv")
    }
}
