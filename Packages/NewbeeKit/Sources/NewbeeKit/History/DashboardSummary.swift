import Foundation

/// Totals for a set of feeds (a day, or the last 24 hours).
public struct FeedTotals: Sendable, Hashable {
    public var feedCount: Int
    public var breastCount: Int
    public var bottleCount: Int
    /// Breastfeeding time, pauses excluded.
    public var breastDuration: TimeInterval
    public var bottleML: Double
    /// Mean start-to-start interval between consecutive feeds in the set; `nil` with fewer than two.
    public var averageInterval: TimeInterval?

    public static let zero = FeedTotals(feedCount: 0, breastCount: 0, bottleCount: 0, breastDuration: 0, bottleML: 0, averageInterval: nil)

    public init(feedCount: Int, breastCount: Int, bottleCount: Int, breastDuration: TimeInterval, bottleML: Double, averageInterval: TimeInterval?) {
        self.feedCount = feedCount
        self.breastCount = breastCount
        self.bottleCount = bottleCount
        self.breastDuration = breastDuration
        self.bottleML = bottleML
        self.averageInterval = averageInterval
    }

    public init(_ entries: [FeedEntry]) {
        let sorted = entries.sorted { $0.start < $1.start }
        feedCount = sorted.count
        breastCount = sorted.count { $0.kind == .breast }
        bottleCount = sorted.count { $0.kind == .bottle }
        breastDuration = sorted.reduce(0) { $0 + $1.breastDuration }
        bottleML = sorted.reduce(0) { $0 + $1.bottleML }
        if let first = sorted.first, let last = sorted.last, sorted.count > 1 {
            // The mean of consecutive gaps telescopes to (last - first) / (n - 1).
            averageInterval = last.start.timeIntervalSince(first.start) / Double(sorted.count - 1)
        } else {
            averageInterval = nil
        }
    }
}

/// Everything the Home screen shows about past feeds (docs/UX_SPEC.md §3.2).
public struct DashboardSummary: Sendable, Hashable {
    /// The most recent finished feed of any kind.
    public var lastFeed: FeedEntry?
    /// The most recent finished breastfeed (its last side drives the suggestion).
    public var lastBreastFeed: FeedEntry?
    /// Feeds that started today (since local midnight).
    public var today: FeedTotals
    /// Feeds that started in the 24 hours before `now` (rolling).
    public var last24Hours: FeedTotals

    public init(entries: [FeedEntry], now: Date, calendar: Calendar = .current) {
        let past = entries.filter { $0.start <= now }
        let newestFirst = past.sorted { $0.start > $1.start }
        lastFeed = newestFirst.first
        lastBreastFeed = newestFirst.first { $0.kind == .breast }
        let midnight = calendar.startOfDay(for: now)
        today = FeedTotals(past.filter { $0.start >= midnight })
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)
        last24Hours = FeedTotals(past.filter { $0.start > dayAgo })
    }

    /// Time since the last feed *started*, the interval parents and clinicians count. Never negative.
    public func timeSinceLastFeed(at now: Date) -> TimeInterval? {
        lastFeed.map { max(0, now.timeIntervalSince($0.start)) }
    }

    /// The side to offer next: opposite the side the last breastfeed ended on. Left with no history.
    public var suggestedNextSide: Side {
        lastBreastFeed?.lastSide?.opposite ?? .left
    }
}
