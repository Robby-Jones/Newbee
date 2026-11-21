import Foundation

/// Which part of a period falls after tracking began, for per-day averages and comparisons.
///
/// Tracking counts from the start of the day of the first log, so that first day is a whole
/// tracked day. Days before it are left out: someone who started logging three days ago shouldn't
/// see "up from 0.9 a day in the previous 14 days".
public struct TrackedSpan: Sendable, Hashable {
    /// Midnight of the first log's day; `nil` treats every day as tracked.
    public var start: Date?

    public init(trackingStart: Date?, calendar: Calendar = .current) {
        start = trackingStart.map { calendar.startOfDay(for: $0) }
    }

    /// The part of `interval` after tracking began, or `nil` if tracking began after it ended.
    public func trackedPart(of interval: DateInterval) -> DateInterval? {
        guard let start else { return interval }
        guard start < interval.end else { return nil }
        return DateInterval(start: max(start, interval.start), end: interval.end)
    }

    /// Tracked days in `interval`, at least 1 so averages never divide by zero.
    public func days(in interval: DateInterval) -> Double {
        max(1, (trackedPart(of: interval)?.duration ?? 0) / 86_400)
    }

    /// An earlier period is worth comparing with once it has 2 tracked days, or is fully tracked
    /// when it's shorter than that (the 24 h before, for the 24 h range).
    public func isComparable(_ previous: DateInterval) -> Bool {
        guard let tracked = trackedPart(of: previous) else { return false }
        let needed = min(2 * 86_400, previous.duration)
        // An hour of slack for clock-change days that run an hour short.
        return tracked.duration >= needed - 3_600
    }
}
