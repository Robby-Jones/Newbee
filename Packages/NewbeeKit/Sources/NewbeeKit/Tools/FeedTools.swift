import Foundation

/// How a feeding interval is measured (docs/PRD.md §3: start to start by default).
public enum IntervalBasis: String, Codable, Sendable, CaseIterable, Hashable {
    /// From one feed's start to the next feed's start.
    case startToStart
    /// From one feed's end to the next feed's start: the rest between feeds.
    case endToStart
}

/// The Tools tab's interval calculator (docs/UX_SPEC.md §3.9).
public enum IntervalCalculator {
    /// Time from `earlier` to `later` by `basis`. Order doesn't matter; never negative.
    public static func interval(between first: FeedEntry, and second: FeedEntry, basis: IntervalBasis) -> TimeInterval {
        let (earlier, later) = first.start <= second.start ? (first, second) : (second, first)
        let from: Date = switch basis {
        case .startToStart: earlier.start
        case .endToStart: earlier.end ?? earlier.start
        }
        return max(0, later.start.timeIntervalSince(from))
    }

    /// Time since `entry` by `basis`. Never negative.
    public static func since(_ entry: FeedEntry, at now: Date, basis: IntervalBasis) -> TimeInterval {
        let from: Date = switch basis {
        case .startToStart: entry.start
        case .endToStart: entry.end ?? entry.start
        }
        return max(0, now.timeIntervalSince(from))
    }
}

/// The Tools tab's side tracker: last side, suggested next side, and recent starting sides.
public struct SideTracker: Sendable, Hashable {
    /// The side the most recent breastfeed ended on.
    public var lastSide: Side?
    /// Opposite of `lastSide`; left with no history.
    public var suggestedNextSide: Side
    /// The starting side of the most recent breastfeeds, newest first.
    public var recentStartingSides: [Side]
    /// Feeding time per side across the breastfeeds counted in `recentStartingSides`.
    public var recentLeft: TimeInterval
    public var recentRight: TimeInterval

    public init(entries: [FeedEntry], recentCount: Int = 5) {
        let breastfeeds = entries.filter { $0.kind == .breast }.sorted { $0.start > $1.start }
        lastSide = breastfeeds.first?.lastSide
        suggestedNextSide = lastSide?.opposite ?? .left
        let recent = breastfeeds.prefix(recentCount)
        recentStartingSides = recent.compactMap { entry in
            if case let .breast(_, _, first, _) = entry.details { return first }
            return nil
        }
        var left: TimeInterval = 0
        var right: TimeInterval = 0
        for entry in recent {
            if case let .breast(l, r, _, _) = entry.details {
                left += l
                right += r
            }
        }
        recentLeft = left
        recentRight = right
    }

    /// The share of recent feeding time on the left, 0...1; `nil` with no time recorded.
    public var leftShare: Double? {
        let total = recentLeft + recentRight
        return total > 0 ? recentLeft / total : nil
    }
}

/// The Tools tab's quick stats: today and this week.
public struct QuickStats: Sendable, Hashable {
    public var today: FeedTotals
    /// Since the start of the current calendar week (the locale's first weekday).
    public var thisWeek: FeedTotals
    /// Mean feeds per day over the days of this week so far (today included).
    public var averageFeedsPerDayThisWeek: Double

    public init(entries: [FeedEntry], now: Date, calendar: Calendar = .current) {
        let past = entries.filter { $0.start <= now }
        let midnight = calendar.startOfDay(for: now)
        today = FeedTotals(past.filter { $0.start >= midnight })
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? midnight
        thisWeek = FeedTotals(past.filter { $0.start >= weekStart })
        let days = (calendar.dateComponents([.day], from: weekStart, to: midnight).day ?? 0) + 1
        averageFeedsPerDayThisWeek = Double(thisWeek.feedCount) / Double(max(1, days))
    }
}
