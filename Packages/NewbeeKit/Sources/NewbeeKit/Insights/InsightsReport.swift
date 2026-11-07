import Foundation

/// The Insights range picker (docs/UX_SPEC.md §3.8).
public enum InsightsRange: String, Sendable, CaseIterable, Hashable, Identifiable {
    /// The rolling 24 hours before now, in hourly buckets.
    case day
    /// Today and the 6 days before it, in daily buckets. Likewise for 14 and 30.
    case week
    case twoWeeks
    case month

    public var id: String { rawValue }

    /// Number of calendar days covered; 1 for the rolling 24 hours.
    public var dayCount: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .twoWeeks: 14
        case .month: 30
        }
    }

    /// The range ending at `now`. Day ranges start at local midnight `dayCount - 1` days ago, so
    /// "7 d" is today plus the six days before it.
    public func interval(endingAt now: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .day:
            return DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        default:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
            return DateInterval(start: start, end: max(start, now))
        }
    }

    /// The equally long range just before `interval(endingAt:)`, for "up from last week".
    public func previousInterval(endingAt now: Date, calendar: Calendar = .current) -> DateInterval {
        let current = interval(endingAt: now, calendar: calendar)
        switch self {
        case .day:
            return DateInterval(start: current.start.addingTimeInterval(-86_400), end: current.start)
        default:
            let start = calendar.date(byAdding: .day, value: -dayCount, to: current.start) ?? current.start
            // Same elapsed share of the last day, so a part-finished today compares fairly.
            let elapsed = now.timeIntervalSince(calendar.startOfDay(for: now))
            let lastDay = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
            let end = min(current.start, lastDay.addingTimeInterval(elapsed))
            return DateInterval(start: start, end: max(start, end))
        }
    }

    /// The earliest feed start any report for this range reads: the start of the previous period.
    public func earliestNeeded(endingAt now: Date, calendar: Calendar = .current) -> Date {
        let previous = previousInterval(endingAt: now, calendar: calendar).start
        // Comparisons always look back at least a week, plus a day of slack.
        let week = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now)) ?? previous
        return min(previous, week)
    }
}

/// One bar of the feeds and bottle-volume charts: an hour (24 h range) or a day.
public struct InsightsBucket: Sendable, Hashable, Identifiable {
    public var start: Date
    public var breastCount: Int
    public var bottleCount: Int
    public var breastDuration: TimeInterval
    public var breastMilkML: Double
    public var formulaML: Double
    public var otherML: Double

    public var id: Date { start }
    public var feedCount: Int { breastCount + bottleCount }
    public var bottleML: Double { breastMilkML + formulaML + otherML }
}

/// The gap from one feed's start to the next one's start.
public struct FeedInterval: Sendable, Hashable, Identifiable {
    /// The later feed's start, which places the point on the time-of-day scatter.
    public var at: Date
    public var length: TimeInterval

    public var id: Date { at }
}

/// One cell of the hour-of-day × day heatmap.
public struct HeatmapCell: Sendable, Hashable, Identifiable {
    public var day: Date
    /// 0–23.
    public var hour: Int
    public var count: Int

    public var id: String { "\(day.timeIntervalSinceReferenceDate)-\(hour)" }
}

/// A current value next to an earlier one, for the comparison chips.
public struct Comparison: Sendable, Hashable {
    public var current: Double
    public var previous: Double

    public init(current: Double, previous: Double) {
        self.current = current
        self.previous = previous
    }

    public var delta: Double { current - previous }

    /// Relative change, e.g. 0.12 for "up 12%". `nil` when there is nothing to compare with.
    public var relativeChange: Double? {
        previous > 0 ? (current - previous) / previous : nil
    }

    /// Changes under 5% (or a nothing-to-compare previous) read as "about the same".
    public var direction: Direction {
        guard let change = relativeChange else { return current > 0 ? .up : .same }
        if change > 0.05 { return .up }
        if change < -0.05 { return .down }
        return .same
    }

    public enum Direction: Sendable, Hashable { case up, down, same }
}

/// Breastfeeding numbers for a range.
public struct BreastInsights: Sendable, Hashable {
    public var sessionCount: Int
    public var totalLeft: TimeInterval
    public var totalRight: TimeInterval
    /// How many sessions started on each side.
    public var startedLeft: Int
    public var startedRight: Int

    public var total: TimeInterval { totalLeft + totalRight }
    public var averageSession: TimeInterval? { sessionCount > 0 ? total / Double(sessionCount) : nil }
    public var averageLeft: TimeInterval? { sessionCount > 0 ? totalLeft / Double(sessionCount) : nil }
    public var averageRight: TimeInterval? { sessionCount > 0 ? totalRight / Double(sessionCount) : nil }
    /// Left's share of breastfeeding time, 0...1; `nil` with no time recorded.
    public var leftShare: Double? { total > 0 ? totalLeft / total : nil }

    /// Which side has had noticeably more time (over 60/40), if either.
    public var favouredSide: Side? {
        guard let share = leftShare else { return nil }
        if share > 0.6 { return .left }
        if share < 0.4 { return .right }
        return nil
    }
}

/// Bottle numbers for a range.
public struct BottleInsights: Sendable, Hashable {
    public var count: Int
    public var breastMilkML: Double
    public var formulaML: Double
    public var otherML: Double

    public var totalML: Double { breastMilkML + formulaML + otherML }
    public var averageML: Double? { count > 0 ? totalML / Double(count) : nil }
}

/// Everything the Insights tab shows for one range (docs/UX_SPEC.md §3.8).
public struct InsightsReport: Sendable, Hashable {
    public var range: InsightsRange
    public var interval: DateInterval
    /// Feeds that started in the range, oldest first.
    public var entries: [FeedEntry]
    /// Hourly buckets for 24 h, daily otherwise, oldest first, including empty ones.
    public var buckets: [InsightsBucket]
    public var intervals: [FeedInterval]
    public var breast: BreastInsights
    public var bottle: BottleInsights
    public var heatmap: [HeatmapCell]

    /// Feeds per elapsed day, this range against the one before it.
    public var feedsPerDay: Comparison
    /// Today so far against yesterday up to the same time.
    public var todayVsYesterday: FeedComparison
    /// The last 7 days against the 7 before them (each up to the current time of day).
    public var weekVsLastWeek: FeedComparison

    /// Some breastfeed in the range was typed in or recovered rather than timed.
    public var includesEstimated: Bool
    /// Fewer than two days with feeds: show what exists, plus a "keep tracking" note.
    public var isSparse: Bool

    public var averageInterval: TimeInterval? {
        intervals.isEmpty ? nil : intervals.reduce(0) { $0 + $1.length } / Double(intervals.count)
    }
    public var shortestInterval: TimeInterval? { intervals.map(\.length).min() }
    public var longestInterval: TimeInterval? { intervals.map(\.length).max() }
    public var isEmpty: Bool { entries.isEmpty }

    public init(entries all: [FeedEntry], range: InsightsRange, now: Date, calendar: Calendar = .current) {
        let past = all.filter { $0.start <= now }.sorted { $0.start < $1.start }
        let interval = range.interval(endingAt: now, calendar: calendar)
        let entries = past.filter { Self.contains(interval, $0.start) }

        self.range = range
        self.interval = interval
        self.entries = entries
        buckets = Self.buckets(entries, range: range, interval: interval, calendar: calendar)
        intervals = zip(entries, entries.dropFirst()).map { previous, next in
            FeedInterval(at: next.start, length: next.start.timeIntervalSince(previous.start))
        }

        var breast = BreastInsights(sessionCount: 0, totalLeft: 0, totalRight: 0, startedLeft: 0, startedRight: 0)
        var bottle = BottleInsights(count: 0, breastMilkML: 0, formulaML: 0, otherML: 0)
        for entry in entries {
            switch entry.details {
            case let .breast(left, right, first, _):
                breast.sessionCount += 1
                breast.totalLeft += left
                breast.totalRight += right
                if first == .left { breast.startedLeft += 1 }
                if first == .right { breast.startedRight += 1 }
            case let .bottle(summary):
                bottle.count += 1
                switch summary.contents {
                case .breastMilk: bottle.breastMilkML += summary.amountML
                case .formula: bottle.formulaML += summary.amountML
                case .other: bottle.otherML += summary.amountML
                }
            }
        }
        self.breast = breast
        self.bottle = bottle
        heatmap = Self.heatmap(entries, interval: interval, calendar: calendar)

        let previous = range.previousInterval(endingAt: now, calendar: calendar)
        let previousCount = past.count { Self.contains(previous, $0.start) }
        // Per elapsed day, so a part-finished today doesn't drag the average down.
        let days = max(1, interval.duration / 86_400)
        let previousDays = max(1, previous.duration / 86_400)
        feedsPerDay = Comparison(current: Double(entries.count) / days, previous: Double(previousCount) / previousDays)

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let elapsedToday = now.timeIntervalSince(today)
        todayVsYesterday = FeedComparison(
            past,
            current: DateInterval(start: today, end: now),
            previous: DateInterval(start: yesterday, end: min(today, yesterday.addingTimeInterval(elapsedToday)))
        )
        let week = InsightsRange.week
        weekVsLastWeek = FeedComparison(
            past,
            current: week.interval(endingAt: now, calendar: calendar),
            previous: week.previousInterval(endingAt: now, calendar: calendar)
        )

        includesEstimated = entries.contains(where: \.isEstimated)
        isSparse = Set(entries.map { calendar.startOfDay(for: $0.start) }).count < 2
    }

    /// Closed at the end so a feed starting exactly "now" counts.
    static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date <= interval.end
    }

    private static func buckets(_ entries: [FeedEntry], range: InsightsRange, interval: DateInterval, calendar: Calendar) -> [InsightsBucket] {
        var starts: [Date] = []
        if range == .day {
            // Whole clock hours, from the hour containing the range start up to now.
            var cursor = calendar.dateInterval(of: .hour, for: interval.start)?.start ?? interval.start
            while cursor <= interval.end {
                starts.append(cursor)
                cursor = cursor.addingTimeInterval(3_600)
            }
        } else {
            var cursor = interval.start
            while cursor <= interval.end, starts.count < range.dayCount {
                starts.append(cursor)
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
            }
        }
        var buckets = starts.map {
            InsightsBucket(start: $0, breastCount: 0, bottleCount: 0, breastDuration: 0, breastMilkML: 0, formulaML: 0, otherML: 0)
        }
        for entry in entries {
            // The last bucket starting at or before the feed.
            guard let index = buckets.lastIndex(where: { $0.start <= entry.start }) else { continue }
            switch entry.details {
            case let .breast(left, right, _, _):
                buckets[index].breastCount += 1
                buckets[index].breastDuration += left + right
            case let .bottle(summary):
                buckets[index].bottleCount += 1
                switch summary.contents {
                case .breastMilk: buckets[index].breastMilkML += summary.amountML
                case .formula: buckets[index].formulaML += summary.amountML
                case .other: buckets[index].otherML += summary.amountML
                }
            }
        }
        return buckets
    }

    private static func heatmap(_ entries: [FeedEntry], interval: DateInterval, calendar: Calendar) -> [HeatmapCell] {
        var counts: [Date: [Int: Int]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.start)
            let hour = calendar.component(.hour, from: entry.start)
            counts[day, default: [:]][hour, default: 0] += 1
        }
        var cells: [HeatmapCell] = []
        var day = calendar.startOfDay(for: interval.start)
        while day <= interval.end {
            for hour in 0..<24 {
                cells.append(HeatmapCell(day: day, hour: hour, count: counts[day]?[hour] ?? 0))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        return cells
    }
}

/// Feeds, breastfeeding time and bottle volume over two periods.
public struct FeedComparison: Sendable, Hashable {
    public var feeds: Comparison
    public var breastDuration: Comparison
    public var bottleML: Comparison

    public init(feeds: Comparison, breastDuration: Comparison, bottleML: Comparison) {
        self.feeds = feeds
        self.breastDuration = breastDuration
        self.bottleML = bottleML
    }

    init(_ entries: [FeedEntry], current: DateInterval, previous: DateInterval) {
        let now = FeedTotals(entries.filter { InsightsReport.contains(current, $0.start) })
        // Half-open at the end so a feed exactly at the boundary isn't counted twice.
        let before = FeedTotals(entries.filter { $0.start >= previous.start && $0.start < previous.end })
        feeds = Comparison(current: Double(now.feedCount), previous: Double(before.feedCount))
        breastDuration = Comparison(current: now.breastDuration, previous: before.breastDuration)
        bottleML = Comparison(current: now.bottleML, previous: before.bottleML)
    }
}
