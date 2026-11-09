import Foundation
import Testing
@testable import NewbeeKit

// Day-based features on the days daylight saving time starts and ends. The rest of the suite
// uses UTC, where every day is 24 hours long; these use real zones, where one day a year is 23
// hours and one is 25.
//
// US 2026: clocks spring forward on Sunday March 8 (02:00 EST → 03:00 EDT) and fall back on
// Sunday November 1 (02:00 EDT → 01:00 EST, so 01:00–02:00 happens twice).

private let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    calendar.firstWeekday = 1
    return calendar
}()

/// A New York wall-clock time. For the repeated hour on November 1 this is the first (EDT) one.
private func ny(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

/// 2026-11-01 01:00 EDT and, an hour later, 01:00 EST.
private let firstOneAM = ny(11, 1, 1)
private let secondOneAM = firstOneAM.addingTimeInterval(3_600)

private func bottle(_ start: Date, ml: Double = 60) -> FeedEntry {
    FeedEntry(id: UUID(), start: start, end: start, details: .bottle(BottleSummary(contents: .formula, amountML: ml)), source: .manual)
}

private func breast(_ start: Date, minutes: Double) -> FeedEntry {
    FeedEntry(id: UUID(), start: start, end: start.addingTimeInterval(minutes * 60),
              details: .breast(left: minutes * 60, right: 0, firstSide: .left, lastSide: .left))
}

private func pump(_ start: Date) -> PumpEntry {
    PumpEntry(startedAt: start, leftML: 50, rightML: 40, timeZoneID: "America/New_York")
}

@Suite("Daylight saving: day boundaries")
struct DaylightSavingDayTests {
    @Test func theRepeatedHourStaysOnOneHistoryDay() {
        let feeds = [
            bottle(ny(11, 1, 0, 30)),
            bottle(firstOneAM.addingTimeInterval(30 * 60)),
            bottle(secondOneAM.addingTimeInterval(30 * 60)),
            bottle(ny(11, 1, 23, 30)), // 24 h 30 min after 00:00 on a 25-hour day
            bottle(ny(11, 2, 0, 10)),
        ]
        let days = HistoryTimeline.days(feeds: feeds, pumps: [pump(secondOneAM)], calendar: newYork)
        #expect(days.map(\.day) == [ny(11, 2, 0), ny(11, 1, 0)])
        #expect(days.map(\.items.count) == [1, 5])
        // Newest first, and the two 01:30s keep their real order.
        let starts = days[1].items.map(\.start)
        #expect(starts == starts.sorted(by: >))
        // Gaps are real elapsed time: 01:30 EDT to 01:30 EST is one hour.
        let secondHalfPast = days[1].items.first { $0.start == secondOneAM.addingTimeInterval(30 * 60) }
        guard case .feed(let row)? = secondHalfPast else { Issue.record("expected the 01:30 EST feed"); return }
        #expect(row.sincePrevious == 3_600)
    }

    @Test func homeTodayCoversTheWhole25HourDay() {
        let entries = [bottle(ny(11, 1, 0, 30)), bottle(ny(10, 31, 23, 59))]
        let summary = DashboardSummary(entries: entries, now: ny(11, 1, 23, 50), calendar: newYork)
        #expect(summary.today.feedCount == 1)
        // 00:30 EDT is 24 h 20 min before 23:50 EST: today, but not in the last 24 hours.
        #expect(summary.last24Hours.feedCount == 0)
    }

    @Test func homeTodayOnThe23HourDay() {
        let entries = [bottle(ny(3, 8, 0, 30)), bottle(ny(3, 8, 3, 30)), bottle(ny(3, 7, 23, 50))]
        let summary = DashboardSummary(entries: entries, now: ny(3, 8, 23, 50), calendar: newYork)
        #expect(summary.today.feedCount == 2)
        #expect(summary.last24Hours.feedCount == 3)
    }

    @Test(arguments: [3, 11])
    func monthGridHasEveryDayOnceAndStartsAtMidnight(month: Int) {
        let grid = FeedCalendar.month(ny(month, 1, 0), entries: [], now: ny(month, 20, 12), calendar: newYork)
        let cells = grid.weeks.flatMap { $0 }
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
        #expect(Set(cells.map(\.day)).count == cells.count)
        #expect(cells.allSatisfy { newYork.startOfDay(for: $0.day) == $0.day })
        let inMonth = cells.filter(\.isInMonth).map(\.dayNumber)
        #expect(inMonth == Array(1...(month == 3 ? 31 : 30)))
    }

    @Test func calendarDaysCountFeedsLateOnTheChangeDays() {
        let entries = [bottle(ny(3, 8, 23, 30)), bottle(ny(11, 1, 23, 30)), bottle(secondOneAM)]
        let pumps = [pump(ny(11, 1, 23, 45))]
        let march = FeedCalendar.month(ny(3, 1, 0), entries: entries, now: ny(11, 20, 12), calendar: newYork)
        #expect(march.weeks.flatMap { $0 }.first { $0.isInMonth && $0.dayNumber == 8 }?.feedCount == 1)
        let november = FeedCalendar.month(ny(11, 1, 0), entries: entries, pumps: pumps, now: ny(11, 20, 12), calendar: newYork)
        let first = november.weeks.flatMap { $0 }.first { $0.isInMonth && $0.dayNumber == 1 }
        #expect(first?.feedCount == 2)
        #expect(first?.pumpCount == 1)
        #expect(FeedCalendar.daySummary(ny(11, 1, 12), entries: entries, calendar: newYork).entries.count == 2)
        #expect(FeedCalendar.dayPumps(ny(11, 1, 12), pumps: pumps, calendar: newYork).count == 1)
    }

    @Test func reportRangesAreWholeLocalDaysAcrossAChange() {
        let fallBackWeek = FeedReportRange.lastDays(7).interval(now: ny(11, 3, 12), calendar: newYork)
        #expect(fallBackWeek.start == ny(10, 28, 0))
        #expect(fallBackWeek.end == ny(11, 4, 0))
        #expect(fallBackWeek.duration == 7 * 86_400 + 3_600)

        let springWeek = FeedReportRange.days(from: ny(3, 7, 15), through: ny(3, 9, 9)).interval(now: ny(3, 20, 12), calendar: newYork)
        #expect(springWeek.start == ny(3, 7, 0))
        #expect(springWeek.end == ny(3, 10, 0))
        #expect(springWeek.duration == 3 * 86_400 - 3_600)
        #expect(FeedReport.fileName(for: springWeek, timeZone: newYork.timeZone) == "Newbee feeding report 2026-03-07 to 2026-03-09.pdf")
    }

    @Test func reportListsEachDayOnceWithItsOwnFeeds() {
        let interval = FeedReportRange.lastDays(7).interval(now: ny(11, 3, 12), calendar: newYork)
        let feeds = [bottle(ny(11, 1, 23, 30)), bottle(secondOneAM), bottle(ny(11, 2, 0, 10))]
        let report = FeedReport(feeds: feeds, pumps: [pump(ny(11, 1, 23, 45))], interval: interval, calendar: newYork)
        #expect(report.days.map(\.day) == (0..<7).map { newYork.date(byAdding: .day, value: $0, to: ny(10, 28, 0))! })
        let first = report.days.first { $0.day == ny(11, 1, 0) }
        #expect(first?.feedCount == 2)
        #expect(first?.pumpCount == 1)
        #expect(report.days.first { $0.day == ny(11, 2, 0) }?.feedCount == 1)
        #expect(report.feedCount == 3)
    }

    @Test func manualEntryOnTheSpringDayMovesPastTheMissingHour() {
        // 02:30 doesn't exist on March 8: the entry defaults to the first time after it.
        let reference = ManualEntryTime.reference(onDay: ny(3, 8, 0), now: ny(3, 9, 2, 30), calendar: newYork)
        #expect(reference == ny(3, 8, 3, 0))
        // The repeated hour keeps the clock time and never goes past now.
        let fallBack = ManualEntryTime.reference(onDay: ny(11, 1, 0), now: ny(11, 2, 1, 30), calendar: newYork)
        #expect(newYork.dateComponents([.day, .hour, .minute], from: fallBack) == DateComponents(day: 1, hour: 1, minute: 30))
        #expect(fallBack < ny(11, 2, 1, 30))
    }
}

@Suite("Daylight saving: Insights")
struct DaylightSavingInsightsTests {
    @Test func twentyFourHoursAcrossFallBackHas25HourlyBars() {
        let feed = bottle(secondOneAM.addingTimeInterval(30 * 60))
        let report = InsightsReport(entries: [feed], range: .day, now: ny(11, 1, 12), calendar: newYork)
        // 24 hours back from 12:00 EST is 13:00 EDT the day before: 25 whole clock hours, every
        // bar an hour long, and both 01:00 bars present.
        #expect(report.buckets.count == 25)
        #expect(zip(report.buckets, report.buckets.dropFirst()).allSatisfy { $1.start.timeIntervalSince($0.start) == 3_600 })
        #expect(report.buckets.filter { newYork.component(.hour, from: $0.start) == 1 }.count == 2)
        #expect(report.buckets.first { $0.start == secondOneAM }?.feedCount == 1)
        #expect(report.buckets.first { $0.start == firstOneAM }?.feedCount == 0)
    }

    @Test func dailyBarsStartAtLocalMidnight() {
        let report = InsightsReport(entries: [bottle(ny(11, 1, 23, 30))], range: .week, now: ny(11, 3, 12), calendar: newYork)
        #expect(report.buckets.count == 7)
        #expect(report.buckets.allSatisfy { newYork.startOfDay(for: $0.start) == $0.start })
        #expect(report.buckets.first { $0.start == ny(11, 1, 0) }?.feedCount == 1)
        // The heatmap has 24 hour rows on the 25-hour day too: both 01:00 hours share one row.
        #expect(report.heatmap.filter { $0.day == ny(11, 1, 0) }.count == 24)
        #expect(report.heatmap.first { $0.day == ny(11, 1, 0) && $0.hour == 23 }?.count == 1)
    }

    @Test func todayVsYesterdayUsesTheSameClockTimeAfterSpringForward() {
        // Monday 10:00, the day after the 23-hour Sunday.
        let entries = [bottle(ny(3, 8, 9, 30)), bottle(ny(3, 8, 10, 30)), bottle(ny(3, 9, 9))]
        let report = InsightsReport(entries: entries, range: .week, now: ny(3, 9, 10), calendar: newYork)
        #expect(report.todayVsYesterday.feeds == Comparison(current: 1, previous: 1))
    }

    @Test func todayVsYesterdayUsesTheSameClockTimeOnTheSpringDay() {
        // Sunday 10:00 has only 9 hours behind it, but yesterday counts up to 10:00 too.
        let entries = [bottle(ny(3, 7, 9, 30)), bottle(ny(3, 7, 10, 30)), bottle(ny(3, 8, 9))]
        let report = InsightsReport(entries: entries, range: .week, now: ny(3, 8, 10), calendar: newYork)
        #expect(report.todayVsYesterday.feeds == Comparison(current: 1, previous: 1))
    }

    @Test func todayVsYesterdayUsesTheSameClockTimeAfterFallBack() {
        // Monday 10:00, the day after the 25-hour Sunday.
        let entries = [bottle(ny(11, 1, 9, 30)), bottle(ny(11, 1, 10, 15)), bottle(ny(11, 2, 9))]
        let report = InsightsReport(entries: entries, range: .week, now: ny(11, 2, 10), calendar: newYork)
        #expect(report.todayVsYesterday.feeds == Comparison(current: 1, previous: 1))
    }

    @Test func weekVsLastWeekEndsAtTheSameClockTime() {
        // A week after spring forward: last week's period ends on Monday March 9 at 10:00.
        let now = ny(3, 16, 10)
        let previous = InsightsRange.week.previousInterval(endingAt: now, calendar: newYork)
        #expect(previous.start == ny(3, 3, 0))
        #expect(previous.end == ny(3, 9, 10))
        let fallBack = InsightsRange.week.previousInterval(endingAt: ny(11, 8, 10), calendar: newYork)
        #expect(fallBack.start == ny(10, 26, 0))
        #expect(fallBack.end == ny(11, 1, 10))
    }
}

@Suite("Daylight saving: timer and reminders")
struct DaylightSavingTimerTests {
    let engine = SessionEngine(timeZone: TimeZone(identifier: "America/New_York")!)

    @Test func feedAcrossSpringForwardKeepsItsRealLength() throws {
        // 01:50 EST to 03:10 EDT is 20 minutes, not 80.
        let clock = TestClock(wall: ny(3, 8, 1, 50))
        var session = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 12 * 60)
        session = try engine.apply(.switchTo(.right), to: session, at: clock.instant()).snapshot
        clock.advance(by: 8 * 60)
        session = try engine.apply(.end, to: session, at: clock.instant()).snapshot
        #expect(session.endedAt == ny(3, 8, 3, 10))
        #expect(approx(session.feedingDuration(at: clock.now), 20 * 60))
        #expect(approx(session.duration(on: .left, at: clock.now), 12 * 60))
        #expect(SessionValidator.isValid(session, now: clock.now))
    }

    @Test func changingTimeZoneMidFeedChangesNothing() throws {
        // A feed started in New York and ended after the phone switched to Tokyo time.
        let clock = TestClock(wall: ny(11, 7, 21))
        let started = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 15 * 60)
        let tokyo = SessionEngine(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let ended = try tokyo.apply(.end, to: started, at: clock.instant()).snapshot
        #expect(ended.timeZoneID == "America/New_York")
        #expect(approx(ended.feedingDuration(at: clock.now), 15 * 60))
        #expect(SessionValidator.isValid(ended, now: clock.now))
    }

    @Test func feedDueIsRealElapsedTimeAcrossFallBack() {
        // 23:30 EDT + 3 h is 01:30 EST (the second 01:30), not the first.
        let planner = ReminderPlanner(calendar: newYork)
        let last = LastFeed(start: ny(10, 31, 23, 30), end: nil, kind: .bottle)
        let settings = ReminderSettings(isEnabled: true, interval: 3 * 3_600)
        let plan = planner.plan(settings: settings, lastFeed: last, active: nil, now: ny(10, 31, 23, 45))
        #expect(plan.first?.fireDate == secondOneAM.addingTimeInterval(30 * 60))
    }

    @Test func quietHoursEndAtTheirClockTimeOnBothChangeNights() {
        let planner = ReminderPlanner(calendar: newYork)
        let settings = ReminderSettings(isEnabled: true, interval: 3 * 3_600, quietHours: .overnight)
        // Fall back: due at 01:30 EST, held until 06:00 EST.
        let fallBack = planner.plan(settings: settings, lastFeed: LastFeed(start: ny(10, 31, 23, 30), end: nil, kind: .bottle),
                                    active: nil, now: ny(10, 31, 23, 45))
        #expect(fallBack.first?.fireDate == ny(11, 1, 6))
        #expect(fallBack.first?.deferredByQuietHours == true)
        // Spring forward: due at 03:30 EDT, held until 06:00 EDT.
        let spring = planner.plan(settings: settings, lastFeed: LastFeed(start: ny(3, 7, 23, 30), end: nil, kind: .bottle),
                                  active: nil, now: ny(3, 7, 23, 45))
        #expect(spring.first?.fireDate == ny(3, 8, 6))
        // Quiet hours ending inside the missing hour end when the clock jumps to 03:00.
        let early = QuietHours(startMinute: 22 * 60, endMinute: 2 * 60 + 30)
        #expect(early.end(after: ny(3, 7, 23), calendar: newYork) == ny(3, 8, 3))
        // Ending inside the repeated hour: the first 01:30, which is when it first reads 01:30.
        let short = QuietHours(startMinute: 22 * 60, endMinute: 90)
        #expect(short.end(after: ny(10, 31, 23), calendar: newYork) == firstOneAM.addingTimeInterval(30 * 60))
    }
}
