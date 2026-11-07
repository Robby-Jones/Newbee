import Foundation

/// One cell of the month grid (docs/UX_SPEC.md §3.5).
public struct CalendarDayCell: Sendable, Hashable, Identifiable {
    /// Midnight at the start of the day.
    public var day: Date
    /// Day of the month, 1–31.
    public var dayNumber: Int
    /// `false` for the leading/trailing days that pad the grid to whole weeks.
    public var isInMonth: Bool
    public var isToday: Bool
    public var isFuture: Bool
    public var feedCount: Int
    public var usedLeft: Bool
    public var usedRight: Bool
    public var hadBottle: Bool

    public var id: Date { day }

    /// Background strength for the cell, 0 (no feeds) to 4 (a very busy day), in five subtle steps.
    public var intensity: Int { FeedCalendar.intensity(forFeedCount: feedCount) }
}

/// A month of feeds laid out as a grid of whole weeks.
public struct CalendarMonth: Sendable, Hashable {
    /// Midnight on the first day of the month.
    public var month: Date
    /// Rows of seven cells, starting on the calendar's first weekday.
    public var weeks: [[CalendarDayCell]]
    /// Feeds that started in the month.
    public var totals: FeedTotals

    public var isEmpty: Bool { totals.feedCount == 0 }
}

/// Builds the Calendar tab's month grid and day summaries. Pure, so it is testable on Linux.
public enum FeedCalendar {
    /// Five steps: none, light (1–4), typical (5–7), busy (8–10), very busy (11+).
    public static func intensity(forFeedCount count: Int) -> Int {
        switch count {
        case ..<1: 0
        case 1...4: 1
        case 5...7: 2
        case 8...10: 3
        default: 4
        }
    }

    /// Midnight on the first day of the month containing `date`.
    public static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// The month `offset` months from the one containing `date`.
    public static func month(byAdding offset: Int, to date: Date, calendar: Calendar = .current) -> Date {
        let start = startOfMonth(date, calendar: calendar)
        return calendar.date(byAdding: .month, value: offset, to: start) ?? start
    }

    /// The half-open interval covering the month containing `date`.
    public static func monthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = startOfMonth(date, calendar: calendar)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(31 * 86_400)
        return DateInterval(start: start, end: end)
    }

    /// The month containing `month`, padded to whole weeks. Days outside the month carry their
    /// own feeds too, so the padding never looks emptier than it was.
    public static func month(
        _ month: Date,
        entries: [FeedEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> CalendarMonth {
        let interval = monthInterval(containing: month, calendar: calendar)
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.start) }
        let today = calendar.startOfDay(for: now)

        // Back up to the first weekday on or before the 1st.
        let weekdayOfFirst = calendar.component(.weekday, from: interval.start)
        let lead = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        var cursor = calendar.date(byAdding: .day, value: -lead, to: interval.start) ?? interval.start

        var weeks: [[CalendarDayCell]] = []
        repeat {
            var week: [CalendarDayCell] = []
            for _ in 0..<7 {
                let day = calendar.startOfDay(for: cursor)
                let feeds = byDay[day] ?? []
                week.append(CalendarDayCell(
                    day: day,
                    dayNumber: calendar.component(.day, from: day),
                    isInMonth: day >= interval.start && day < interval.end,
                    isToday: day == today,
                    isFuture: day > today,
                    feedCount: feeds.count,
                    usedLeft: feeds.contains { $0.duration(on: .left) > 0 },
                    usedRight: feeds.contains { $0.duration(on: .right) > 0 },
                    hadBottle: feeds.contains { $0.kind == .bottle }
                ))
                // Step by calendar day (not 86 400 s) so DST changes don't skip or repeat a day.
                cursor = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            }
            weeks.append(week)
        } while cursor < interval.end

        // DateInterval.contains includes the end, so compare by hand (half-open).
        let inMonth = entries.filter { $0.start >= interval.start && $0.start < interval.end }
        return CalendarMonth(month: interval.start, weeks: weeks, totals: FeedTotals(inMonth))
    }

    /// Feeds that started on `day`, oldest first, and their totals.
    public static func daySummary(
        _ day: Date,
        entries: [FeedEntry],
        calendar: Calendar = .current
    ) -> (entries: [FeedEntry], totals: FeedTotals) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let feeds = entries.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
        return (feeds, FeedTotals(feeds))
    }
}

extension FeedEntry {
    /// Time on one breast; zero for bottles.
    public func duration(on side: Side) -> TimeInterval {
        guard case let .breast(left, right, _, _) = details else { return 0 }
        return side == .left ? left : right
    }

    /// Bottle contents; `nil` for breastfeeds.
    public var bottleContents: BottleContents? {
        if case let .bottle(bottle) = details { return bottle.contents }
        return nil
    }

    /// The breast side used first; `nil` for bottles.
    public var firstSide: Side? {
        if case let .breast(_, _, first, _) = details { return first }
        return nil
    }

    /// Times that were typed in or reconstructed rather than timed live. Bottles are always typed
    /// in, so only breastfeeds count as estimated.
    public var isEstimated: Bool {
        guard kind == .breast else { return false }
        return needsReview || source != .timer
    }
}
