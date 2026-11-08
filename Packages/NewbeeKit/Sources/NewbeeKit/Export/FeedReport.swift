import Foundation

/// The date ranges the PDF report offers: the last 7, 14 or 30 days, or any span of whole days.
public enum FeedReportRange: Sendable, Hashable {
    /// Today and the `n - 1` days before it.
    case lastDays(Int)
    /// From the first day through the last day, both included. Order doesn't matter.
    case days(from: Date, through: Date)

    /// The presets shown first in the picker.
    public static let presets: [FeedReportRange] = [.lastDays(7), .lastDays(14), .lastDays(30)]

    /// Whole local days, from midnight of the first day to midnight after the last one.
    /// A range that reaches into the future stops at the end of today.
    public func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        switch self {
        case .lastDays(let count):
            let start = calendar.date(byAdding: .day, value: -(max(1, count) - 1), to: today) ?? today
            return DateInterval(start: start, end: endOfToday)
        case let .days(from, through):
            let first = calendar.startOfDay(for: min(from, through))
            let last = calendar.startOfDay(for: max(from, through))
            let end = min(calendar.date(byAdding: .day, value: 1, to: last) ?? last, endOfToday)
            return DateInterval(start: min(first, end), end: end)
        }
    }
}

/// Everything the PDF feeding report shows for a range (docs/PRD.md #21): a summary for page one
/// and a day-by-day log. Plain values, so the numbers are tested on Linux and the app only draws.
public struct FeedReport: Sendable, Hashable {
    /// Totals for one calendar day, plus that day's feeds and pumping sessions oldest first.
    public struct Day: Sendable, Hashable, Identifiable {
        /// Local midnight.
        public var day: Date
        public var breastCount: Int
        public var bottleCount: Int
        public var breastDuration: TimeInterval
        public var bottleML: Double
        public var pumpCount: Int
        public var pumpML: Double
        /// Feeds and pumping sessions, oldest first. A feed's gap is to the feed before it, which
        /// may be on an earlier day; pumping never shortens a gap.
        public var items: [HistoryItem]

        public var id: Date { day }
        public var feedCount: Int { breastCount + bottleCount }
    }

    public struct BreastSummary: Sendable, Hashable {
        public var count: Int
        public var totalLeft: TimeInterval
        public var totalRight: TimeInterval
        /// How many feeds started on each side.
        public var startedLeft: Int
        public var startedRight: Int

        public var total: TimeInterval { totalLeft + totalRight }
        public var averageFeed: TimeInterval? { count > 0 ? total / Double(count) : nil }
        /// Left's share of breastfeeding time, 0...1; `nil` with no time recorded.
        public var leftShare: Double? { total > 0 ? totalLeft / total : nil }
    }

    public struct BottleSummaryTotals: Sendable, Hashable {
        public var count: Int
        public var breastMilkML: Double
        public var formulaML: Double
        public var otherML: Double

        public var totalML: Double { breastMilkML + formulaML + otherML }
        public var averageML: Double? { count > 0 ? totalML / Double(count) : nil }
    }

    public struct PumpSummary: Sendable, Hashable {
        public var count: Int
        public var leftML: Double
        public var rightML: Double

        public var totalML: Double { leftML + rightML }
    }

    /// Whole local days covered, midnight to midnight.
    public var interval: DateInterval
    /// Every day in the range, oldest first, including days with nothing logged.
    public var days: [Day]
    public var breast: BreastSummary
    public var bottle: BottleSummaryTotals
    public var pump: PumpSummary
    /// Start-to-start gaps between consecutive feeds in the range.
    public var averageGap: TimeInterval?
    public var longestGap: TimeInterval?

    public var dayCount: Int { days.count }
    public var feedCount: Int { breast.count + bottle.count }
    public var isEmpty: Bool { feedCount == 0 && pump.count == 0 }

    /// Average per calendar day in the range. Today counts as a whole day even if it isn't over.
    public var feedsPerDay: Double { perDay(Double(feedCount)) }
    public var bottleMLPerDay: Double { perDay(bottle.totalML) }
    public var breastDurationPerDay: TimeInterval { perDay(breast.total) }
    public var pumpMLPerDay: Double { perDay(pump.totalML) }

    /// Days that have any feed or pumping session, for the log pages.
    public var loggedDays: [Day] { days.filter { !$0.items.isEmpty } }

    private func perDay(_ value: Double) -> Double {
        dayCount > 0 ? value / Double(dayCount) : 0
    }

    /// Builds the report from finished feeds and pumping sessions. Anything starting outside
    /// `interval` is ignored, so callers may pass a wider fetch.
    public init(feeds: [FeedEntry], pumps: [PumpEntry], interval: DateInterval, calendar: Calendar = .current) {
        self.interval = interval
        let inRange = { (date: Date) in date >= interval.start && date < interval.end }
        let feeds = feeds.filter { inRange($0.start) }
            .sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
        let pumps = pumps.filter { inRange($0.startedAt) }

        var breast = BreastSummary(count: 0, totalLeft: 0, totalRight: 0, startedLeft: 0, startedRight: 0)
        var bottle = BottleSummaryTotals(count: 0, breastMilkML: 0, formulaML: 0, otherML: 0)
        for feed in feeds {
            switch feed.details {
            case let .breast(left, right, first, _):
                breast.count += 1
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
        self.pump = PumpSummary(
            count: pumps.count,
            leftML: pumps.reduce(0) { $0 + $1.leftML },
            rightML: pumps.reduce(0) { $0 + $1.rightML }
        )

        let gaps = zip(feeds, feeds.dropFirst()).map { $1.start.timeIntervalSince($0.start) }
        averageGap = gaps.isEmpty ? nil : gaps.reduce(0, +) / Double(gaps.count)
        longestGap = gaps.max()

        // Feeds and pumps grouped by day, oldest first (History's own grouping, reversed).
        var itemsByDay: [Date: [HistoryItem]] = [:]
        for historyDay in HistoryTimeline.days(feeds: feeds, pumps: pumps, calendar: calendar) {
            itemsByDay[historyDay.day] = historyDay.items.reversed()
        }

        var days: [Day] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            let items = itemsByDay[cursor] ?? []
            var day = Day(day: cursor, breastCount: 0, bottleCount: 0, breastDuration: 0, bottleML: 0,
                          pumpCount: 0, pumpML: 0, items: items)
            for item in items {
                switch item {
                case .feed(let row):
                    switch row.entry.details {
                    case .breast:
                        day.breastCount += 1
                        day.breastDuration += row.entry.breastDuration
                    case .bottle(let summary):
                        day.bottleCount += 1
                        day.bottleML += summary.amountML
                    }
                case .pump(let entry):
                    day.pumpCount += 1
                    day.pumpML += entry.totalML
                }
            }
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        self.days = days
    }

    /// "Newbee feeding report 2026-10-26 to 2026-11-08.pdf".
    public static func fileName(for interval: DateInterval, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.string(from: interval.start)
        // The interval ends at midnight after the last day.
        let last = formatter.string(from: interval.end.addingTimeInterval(-1))
        return first == last
            ? "Newbee feeding report \(first).pdf"
            : "Newbee feeding report \(first) to \(last).pdf"
    }
}
