import Foundation
import Testing
@testable import NewbeeKit

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Saturday 2026-11-07 00:00 UTC.
private let midnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 7))!

private func at(_ hour: Double, day: Int = 0) -> Date { midnight.addingTimeInterval(Double(day) * 86_400 + hour * 3600) }

private func breast(_ start: Date, left: TimeInterval, right: TimeInterval, first: Side = .left) -> FeedEntry {
    FeedEntry(id: UUID(), start: start, end: start.addingTimeInterval(left + right),
              details: .breast(left: left, right: right, firstSide: first, lastSide: right > 0 ? .right : .left))
}

private func bottle(_ start: Date, ml: Double, contents: BottleContents = .formula) -> FeedEntry {
    FeedEntry(id: UUID(), start: start, end: start, details: .bottle(BottleSummary(contents: contents, amountML: ml)), source: .manual)
}

private func pump(_ start: Date, left: Double, right: Double) -> PumpEntry {
    PumpEntry(startedAt: start, leftML: left, rightML: right, timeZoneID: "UTC")
}

@Suite("PDF report ranges")
struct FeedReportRangeTests {
    @Test func lastDaysCoversTodayAndTheDaysBefore() {
        let interval = FeedReportRange.lastDays(7).interval(now: at(15), calendar: utc)
        #expect(interval.start == at(0, day: -6))
        #expect(interval.end == at(0, day: 1))
    }

    @Test func customRangeIncludesBothDaysInEitherOrder() {
        let interval = FeedReportRange.days(from: at(20, day: -2), through: at(3, day: -5)).interval(now: at(15), calendar: utc)
        #expect(interval.start == at(0, day: -5))
        #expect(interval.end == at(0, day: -1))
    }

    @Test func customRangeStopsAtTheEndOfToday() {
        let interval = FeedReportRange.days(from: at(1, day: -1), through: at(1, day: 4)).interval(now: at(15), calendar: utc)
        #expect(interval.end == at(0, day: 1))
    }
}

@Suite("PDF report")
struct FeedReportTests {
    private let interval = DateInterval(start: at(0, day: -2), end: at(0, day: 1))

    @Test func summarizesFeedsBottlesAndPumping() {
        let report = FeedReport(
            feeds: [
                breast(at(2, day: -2), left: 12 * 60, right: 9 * 60),
                bottle(at(5, day: -2), ml: 90),
                breast(at(8, day: -1), left: 10 * 60, right: 0, first: .right),
                bottle(at(11, day: -1), ml: 60, contents: .breastMilk),
                bottle(at(1, day: -3), ml: 500), // before the range
            ],
            pumps: [pump(at(6, day: -2), left: 40, right: 50), pump(at(9, day: 2), left: 1, right: 1)],
            interval: interval,
            calendar: utc
        )
        #expect(report.dayCount == 3)
        #expect(report.feedCount == 4)
        #expect(report.breast.count == 2)
        #expect(report.breast.total == 31 * 60)
        #expect(report.breast.startedLeft == 1)
        #expect(report.breast.startedRight == 1)
        #expect(report.bottle.count == 2)
        #expect(report.bottle.formulaML == 90)
        #expect(report.bottle.breastMilkML == 60)
        #expect(report.pump.count == 1)
        #expect(report.pump.totalML == 90)
        #expect(approx(report.feedsPerDay, 4.0 / 3))
        #expect(report.bottleMLPerDay == 50)
        // Gaps 3 h, 27 h, 3 h.
        #expect(approx(report.averageGap, 11 * 3600))
        #expect(approx(report.longestGap, 27 * 3600))
    }

    @Test func listsEveryDayOldestFirstWithItemsInOrder() {
        let report = FeedReport(
            feeds: [bottle(at(5, day: -2), ml: 90), breast(at(2, day: -2), left: 600, right: 600)],
            pumps: [pump(at(3, day: -2), left: 40, right: 0)],
            interval: interval,
            calendar: utc
        )
        #expect(report.days.map(\.day) == [at(0, day: -2), at(0, day: -1), at(0)])
        let first = report.days[0]
        #expect(first.feedCount == 2)
        #expect(first.pumpCount == 1)
        #expect(first.pumpML == 40)
        #expect(first.items.map(\.start) == [at(2, day: -2), at(3, day: -2), at(5, day: -2)])
        #expect(report.days[1].items.isEmpty)
        #expect(report.loggedDays.count == 1)
        if case .feed(let row) = first.items[2] {
            // The pumping session in between doesn't shorten the gap.
            #expect(approx(row.sincePrevious, 3 * 3600))
        } else {
            Issue.record("Expected the bottle last")
        }
    }

    @Test func anEmptyRangeHasNoGaps() {
        let report = FeedReport(feeds: [], pumps: [], interval: interval, calendar: utc)
        #expect(report.isEmpty)
        #expect(report.averageGap == nil)
        #expect(report.feedsPerDay == 0)
        #expect(report.days.count == 3)
    }

    @Test func namesTheFileByItsDays() {
        let zone = TimeZone(identifier: "UTC")!
        #expect(FeedReport.fileName(for: interval, timeZone: zone) == "Newbee feeding report 2026-11-05 to 2026-11-07.pdf")
        #expect(FeedReport.fileName(for: DateInterval(start: at(0), end: at(0, day: 1)), timeZone: zone) == "Newbee feeding report 2026-11-07.pdf")
    }
}
