import Foundation
import Testing
@testable import NewbeeKit

/// Fixed calendar (Monday-first, UTC) so grids and buckets don't depend on the test machine.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}()

/// 2026-11-07 00:00 UTC, a Saturday.
private let midnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 7))!

private func at(_ hour: Double, day: Int = 0) -> Date {
    midnight.addingTimeInterval(Double(day) * 86_400 + hour * 3_600)
}

private func breast(_ start: Date, left: TimeInterval, right: TimeInterval, first: Side = .left, source: EntrySource = .timer) -> FeedEntry {
    let last: Side = (first == .left ? right : left) > 0 ? first.opposite : first
    return FeedEntry(id: UUID(), start: start, end: start.addingTimeInterval(left + right),
                     details: .breast(left: left, right: right, firstSide: first, lastSide: last), source: source)
}

private func bottle(_ start: Date, ml: Double, contents: BottleContents = .formula) -> FeedEntry {
    FeedEntry(id: UUID(), start: start, end: start, details: .bottle(BottleSummary(contents: contents, amountML: ml)), source: .manual)
}

@Suite("Feed calendar")
struct FeedCalendarTests {
    @Test func monthGridIsWholeWeeksStartingOnFirstWeekday() {
        let month = FeedCalendar.month(midnight, entries: [], now: at(9), calendar: utc)
        // November 2026 starts on a Sunday: with Monday first, six leading October days and
        // 5 + 1 weeks in all (Nov 30 is a Monday).
        #expect(month.month == utc.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(month.weeks.allSatisfy { $0.count == 7 })
        #expect(month.weeks.count == 6)
        let first = month.weeks[0]
        #expect(first[0].dayNumber == 26 && !first[0].isInMonth)
        #expect(first[6].dayNumber == 1 && first[6].isInMonth)
        #expect(utc.component(.weekday, from: first[0].day) == 2)
        #expect(month.weeks.flatMap { $0 }.filter(\.isInMonth).count == 30)
        #expect(month.isEmpty)
    }

    @Test func cellsCarryDotsTodayAndFuture() {
        let entries = [
            breast(at(2), left: 600, right: 0),
            breast(at(5), left: 0, right: 300, first: .right),
            bottle(at(8), ml: 90),
            bottle(at(10, day: -1), ml: 60),
        ]
        let month = FeedCalendar.month(midnight, entries: entries, now: at(12), calendar: utc)
        let cells = month.weeks.flatMap { $0 }
        let today = cells.first { $0.isToday }!
        #expect(today.day == midnight)
        #expect(today.feedCount == 3)
        #expect(today.usedLeft && today.usedRight && today.hadBottle)
        #expect(today.intensity == 1)
        let yesterday = cells.first { $0.day == at(0, day: -1) }!
        #expect(yesterday.hadBottle && !yesterday.usedLeft && !yesterday.usedRight)
        #expect(cells.first { $0.day == at(0, day: 1) }!.isFuture)
        #expect(!today.isFuture)
        #expect(month.totals.feedCount == 4)
        #expect(month.totals.bottleML == 150)
    }

    @Test func pumpsMarkTheirDayButAreNotFeeds() {
        let pumps = [
            PumpEntry(startedAt: at(6), leftML: 60, rightML: 40),
            PumpEntry(startedAt: at(14), leftML: 50, rightML: 0),
            PumpEntry(startedAt: at(9, day: -1), leftML: 30, rightML: 30),
            // Padding day in October: marked, but not in the month total.
            PumpEntry(startedAt: utc.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))!, leftML: 80, rightML: 0),
        ]
        let month = FeedCalendar.month(midnight, entries: [], pumps: pumps, now: at(15), calendar: utc)
        let cells = month.weeks.flatMap { $0 }
        let today = cells.first { $0.isToday }!
        #expect(today.pumpCount == 2 && today.hadPump)
        #expect(today.feedCount == 0 && today.intensity == 0)
        #expect(cells.first { $0.day == at(0, day: -1) }!.pumpCount == 1)
        #expect(cells.first { !$0.isInMonth && $0.dayNumber == 30 }!.hadPump)
        #expect(month.pumps.count == 3)
        #expect(month.pumps.totalML == 210)
        #expect(month.totals.feedCount == 0)
        #expect(!month.isEmpty)
        #expect(FeedCalendar.dayPumps(midnight, pumps: pumps, calendar: utc).map(\.startedAt) == [at(6), at(14)])
    }

    @Test func intensityHasFiveSteps() {
        #expect([0, 1, 4, 5, 7, 8, 10, 11, 20].map(FeedCalendar.intensity(forFeedCount:)) == [0, 1, 1, 2, 2, 3, 3, 4, 4])
    }

    @Test func monthNavigationAndInterval() {
        let december = FeedCalendar.month(byAdding: 1, to: at(15, day: 10), calendar: utc)
        #expect(december == utc.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let interval = FeedCalendar.monthInterval(containing: midnight, calendar: utc)
        #expect(interval.duration == 30 * 86_400)
    }

    @Test func daySummaryIsTheDaysFeedsOldestFirst() {
        let late = breast(at(23.5), left: 900, right: 0)
        let early = bottle(at(1), ml: 90)
        let nextDay = bottle(at(0.5, day: 1), ml: 60)
        let summary = FeedCalendar.daySummary(at(14), entries: [late, nextDay, early], calendar: utc)
        #expect(summary.entries.map(\.id) == [early.id, late.id])
        #expect(summary.totals.feedCount == 2)
        #expect(approx(summary.totals.averageInterval, 22.5 * 3_600))
    }
}

@Suite("Insights report")
struct InsightsReportTests {
    @Test func dayRangesStartAtMidnight() {
        let now = at(9.5)
        let week = InsightsRange.week.interval(endingAt: now, calendar: utc)
        #expect(week.start == at(0, day: -6))
        #expect(week.end == now)
        let previous = InsightsRange.week.previousInterval(endingAt: now, calendar: utc)
        #expect(previous.start == at(0, day: -13))
        #expect(previous.end == at(9.5, day: -7))
        let day = InsightsRange.day.interval(endingAt: now, calendar: utc)
        #expect(day.duration == 86_400)
    }

    @Test func bucketsCountFeedsAndVolumesPerDay() {
        let entries = [
            breast(at(2), left: 600, right: 300),
            bottle(at(4), ml: 90, contents: .breastMilk),
            bottle(at(6), ml: 60, contents: .formula),
            breast(at(3, day: -2), left: 300, right: 300),
            breast(at(3, day: -10), left: 300, right: 300), // outside the week
        ]
        let report = InsightsReport(entries: entries, range: .week, now: at(12), calendar: utc)
        #expect(report.buckets.count == 7)
        #expect(report.buckets.first?.start == at(0, day: -6))
        let today = report.buckets.last!
        #expect(today.start == midnight)
        #expect(today.breastCount == 1 && today.bottleCount == 2)
        #expect(today.breastMilkML == 90 && today.formulaML == 60 && today.bottleML == 150)
        #expect(report.buckets[4].breastCount == 1)
        #expect(report.entries.count == 4)
    }

    @Test func dayRangeUsesHourlyBuckets() {
        let report = InsightsReport(entries: [breast(at(11.25), left: 600, right: 0)], range: .day, now: at(11.5), calendar: utc)
        // 11:00 yesterday (the hour containing 11:30) ... 11:00 today.
        #expect(report.buckets.count == 25)
        #expect(report.buckets.first?.start == at(11, day: -1))
        #expect(report.buckets.last?.start == at(11))
        #expect(report.buckets.last?.feedCount == 1)
    }

    @Test func intervalsAreStartToStartWithinTheRange() {
        let entries = [
            breast(at(1), left: 600, right: 0),
            bottle(at(3.5), ml: 90),
            breast(at(5), left: 600, right: 0),
            breast(at(9), left: 600, right: 0),
        ]
        let report = InsightsReport(entries: entries, range: .week, now: at(12), calendar: utc)
        #expect(zip(report.intervals.map(\.length), [2.5, 1.5, 4.0]).allSatisfy { approx($0, $1 * 3_600) })
        #expect(report.intervals.count == 3)
        #expect(report.intervals.first?.at == at(3.5))
        #expect(approx(report.averageInterval, 8.0 / 3 * 3_600))
        #expect(approx(report.shortestInterval, 1.5 * 3_600))
        #expect(approx(report.longestInterval, 4 * 3_600))
    }

    @Test func breastAndBottleTotals() {
        let entries = [
            breast(at(1), left: 12 * 60, right: 9 * 60, first: .left),
            breast(at(4), left: 4 * 60, right: 15 * 60, first: .right),
            breast(at(7), left: 10 * 60, right: 0, first: .left),
            bottle(at(9), ml: 90, contents: .breastMilk),
            bottle(at(10), ml: 120, contents: .formula),
        ]
        let report = InsightsReport(entries: entries, range: .week, now: at(12), calendar: utc)
        #expect(report.breast.sessionCount == 3)
        #expect(report.breast.totalLeft == 26 * 60)
        #expect(report.breast.totalRight == 24 * 60)
        #expect(approx(report.breast.averageSession, 50.0 / 3 * 60))
        #expect(report.breast.startedLeft == 2 && report.breast.startedRight == 1)
        #expect(approx(report.breast.leftShare, 0.52))
        #expect(report.breast.favouredSide == nil)
        #expect(report.bottle.count == 2)
        #expect(report.bottle.totalML == 210)
        #expect(report.bottle.averageML == 105)
    }

    @Test func favouredSideNeedsAClearImbalance() {
        let entries = [breast(at(1), left: 20 * 60, right: 5 * 60)]
        let report = InsightsReport(entries: entries, range: .week, now: at(12), calendar: utc)
        #expect(report.breast.favouredSide == .left)
    }

    @Test func comparesTodayWithYesterdayAtTheSameTime() {
        let entries = [
            breast(at(1), left: 600, right: 0),
            breast(at(4), left: 600, right: 0),
            breast(at(7), left: 600, right: 0),
            bottle(at(2, day: -1), ml: 60),
            bottle(at(6, day: -1), ml: 60),
            bottle(at(11, day: -1), ml: 60), // after "this time yesterday"
        ]
        let report = InsightsReport(entries: entries, range: .week, now: at(8), calendar: utc)
        #expect(report.todayVsYesterday.feeds == Comparison(current: 3, previous: 2))
        #expect(report.todayVsYesterday.feeds.direction == .up)
        #expect(report.todayVsYesterday.bottleML == Comparison(current: 0, previous: 120))
        #expect(report.todayVsYesterday.bottleML.direction == .down)
        #expect(approx(report.todayVsYesterday.feeds.relativeChange, 0.5))
    }

    @Test func comparesThisWeekWithLastWeek() {
        var entries: [FeedEntry] = []
        for day in -6...0 { entries.append(breast(at(1, day: day), left: 600, right: 0)) }
        for day in -13...(-7) { entries.append(breast(at(1, day: day), left: 600, right: 0)) }
        entries.append(breast(at(2, day: -9), left: 600, right: 0))
        let report = InsightsReport(entries: entries, range: .week, now: at(12), calendar: utc)
        #expect(report.weekVsLastWeek.feeds == Comparison(current: 7, previous: 8))
        #expect(report.feedsPerDay.current < report.feedsPerDay.previous)
    }

    @Test func comparisonDirectionIgnoresSmallChanges() {
        #expect(Comparison(current: 8.2, previous: 8).direction == .same)
        #expect(Comparison(current: 0, previous: 0).direction == .same)
        #expect(Comparison(current: 2, previous: 0).direction == .up)
        #expect(Comparison(current: 2, previous: 0).relativeChange == nil)
    }

    @Test func flagsEstimatedBreastfeedsOnly() {
        let timed = InsightsReport(entries: [breast(at(1), left: 600, right: 0), bottle(at(2), ml: 90)], range: .week, now: at(12), calendar: utc)
        #expect(!timed.includesEstimated)
        let manual = InsightsReport(entries: [breast(at(1), left: 600, right: 0, source: .manual)], range: .week, now: at(12), calendar: utc)
        #expect(manual.includesEstimated)
    }

    @Test func sparseUntilTwoDaysHaveFeeds() {
        let oneDay = InsightsReport(entries: [breast(at(1), left: 600, right: 0)], range: .week, now: at(12), calendar: utc)
        #expect(oneDay.isSparse)
        #expect(!oneDay.isEmpty)
        let twoDays = InsightsReport(entries: [breast(at(1), left: 600, right: 0), breast(at(1, day: -1), left: 600, right: 0)], range: .week, now: at(12), calendar: utc)
        #expect(!twoDays.isSparse)
        #expect(InsightsReport(entries: [], range: .month, now: at(12), calendar: utc).isEmpty)
    }

    @Test func heatmapCountsFeedsByDayAndHour() {
        let entries = [breast(at(2.1), left: 600, right: 0), bottle(at(2.9), ml: 60), breast(at(14, day: -1), left: 600, right: 0)]
        let report = InsightsReport(entries: entries, range: .week, now: at(20), calendar: utc)
        #expect(report.heatmap.count == 7 * 24)
        #expect(report.heatmap.first { $0.day == midnight && $0.hour == 2 }?.count == 2)
        #expect(report.heatmap.first { $0.day == at(0, day: -1) && $0.hour == 14 }?.count == 1)
        #expect(report.heatmap.reduce(0) { $0 + $1.count } == 3)
    }

    @Test func futureFeedsAreIgnored() {
        let report = InsightsReport(entries: [breast(at(13), left: 600, right: 0)], range: .week, now: at(12), calendar: utc)
        #expect(report.isEmpty)
    }

    @Test func earliestNeededCoversThePreviousPeriod() {
        #expect(InsightsRange.month.earliestNeeded(endingAt: at(12), calendar: utc) == at(0, day: -59))
        #expect(InsightsRange.day.earliestNeeded(endingAt: at(12), calendar: utc) == at(0, day: -14))
    }
}

@Suite("Bar labels")
struct BarLabelsTests {
    @Test func densityFollowsBarCount() {
        #expect(BarLabels.density(barCount: 7) == .roomy)
        #expect(BarLabels.density(barCount: 14) == .compact)
        #expect(BarLabels.density(barCount: 24) == .dense)
        #expect(BarLabels.density(barCount: 30) == .dense)
    }

    @Test func segmentLabelsSkipSingleTinyAndDense() {
        // Two segments, both big enough.
        #expect(BarLabels.showsSegmentLabel(5, in: [5, 3], tallest: 10, density: .roomy))
        #expect(BarLabels.showsSegmentLabel(3, in: [5, 3], tallest: 10, density: .compact))
        // Too small next to the tallest bar.
        #expect(!BarLabels.showsSegmentLabel(1, in: [8, 1], tallest: 10, density: .roomy))
        // Only one segment: the total says it already.
        #expect(!BarLabels.showsSegmentLabel(8, in: [8, 0, 0], tallest: 10, density: .roomy))
        // Zero, and dense charts.
        #expect(!BarLabels.showsSegmentLabel(0, in: [8, 0], tallest: 10, density: .roomy))
        #expect(!BarLabels.showsSegmentLabel(5, in: [5, 5], tallest: 10, density: .dense))
    }

    @Test func axisLeavesRoomForTotals() {
        #expect(BarLabels.axisTop(tallest: 10) > 10)
        #expect(BarLabels.axisTop(tallest: 0) == 1)
    }
}
