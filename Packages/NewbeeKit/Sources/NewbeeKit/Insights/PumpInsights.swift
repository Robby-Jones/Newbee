import Foundation

/// One bar of the pumping chart: an hour (24 h range) or a day. Entries logged per side add to
/// `leftML`/`rightML`; total-only entries add to `totalOnlyML` instead, so the chart can show
/// them as their own part rather than as a made-up even split.
public struct PumpBucket: Sendable, Hashable, Identifiable {
    public var start: Date
    public var leftML: Double
    public var rightML: Double
    public var totalOnlyML: Double

    public var id: Date { start }
    public var totalML: Double { leftML + rightML + totalOnlyML }
}

/// Everything the Insights Pumping card shows for one range.
public struct PumpInsights: Sendable, Hashable {
    public var range: InsightsRange
    public var interval: DateInterval
    /// Sessions that started in the range, oldest first.
    public var entries: [PumpEntry]
    /// Same bars as the feeds chart: hourly for 24 h, daily otherwise, including empty ones.
    public var buckets: [PumpBucket]
    /// Milliliters pumped per tracked day, this range against the one before it. For 24 h it's
    /// the plain total of each 24 h instead.
    public var perDay: Comparison
    /// The previous period had enough tracked time to compare with (`TrackedSpan`).
    public var hasPreviousPeriod: Bool

    public var sessionCount: Int { entries.count }
    public var totalML: Double { entries.reduce(0) { $0 + $1.totalML } }
    public var averageSessionML: Double? { entries.isEmpty ? nil : totalML / Double(entries.count) }
    /// The range has a total-only entry, so the chart needs its "Total" part.
    public var hasTotalOnly: Bool { entries.contains(where: \.isTotalOnly) }
    /// The range has an entry logged per side.
    public var hasSided: Bool { entries.contains { !$0.isTotalOnly } }

    /// `trackingStart` is the first pumping session ever logged; `nil` treats every day as tracked.
    public init(pumps all: [PumpEntry], range: InsightsRange, now: Date, trackingStart: Date? = nil, calendar: Calendar = .current) {
        let past = all.filter { $0.startedAt <= now }.sorted { $0.startedAt < $1.startedAt }
        let interval = range.interval(endingAt: now, calendar: calendar)
        let entries = past.filter { InsightsReport.contains(interval, $0.startedAt) }
        self.range = range
        self.interval = interval
        self.entries = entries

        var buckets = InsightsReport.bucketStarts(range: range, interval: interval, calendar: calendar).map {
            PumpBucket(start: $0, leftML: 0, rightML: 0, totalOnlyML: 0)
        }
        for entry in entries {
            guard let index = buckets.lastIndex(where: { $0.start <= entry.startedAt }) else { continue }
            if entry.isTotalOnly {
                buckets[index].totalOnlyML += entry.totalML
            } else {
                buckets[index].leftML += entry.leftML
                buckets[index].rightML += entry.rightML
            }
        }
        self.buckets = buckets

        let previous = range.previousInterval(endingAt: now, calendar: calendar)
        let previousML = past.filter { InsightsReport.contains(previous, $0.startedAt) }.reduce(0) { $0 + $1.totalML }
        let span = TrackedSpan(trackingStart: trackingStart, calendar: calendar)
        hasPreviousPeriod = span.isComparable(previous)
        let total = entries.reduce(0) { $0 + $1.totalML }
        if range == .day {
            perDay = Comparison(current: total, previous: hasPreviousPeriod ? previousML : 0)
        } else {
            perDay = Comparison(
                current: total / span.days(in: interval),
                previous: hasPreviousPeriod ? previousML / span.days(in: previous) : 0
            )
        }
    }
}
