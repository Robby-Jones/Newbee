import Foundation

/// Which bars of a feeds or bottle chart get an x-axis label, and how each label is anchored.
///
/// Labels sit under the middle of their bar and count back from the newest bar, so today (or
/// the current hour) is always labeled. The newest label hangs left of its bar and a label on
/// the very first bar hangs right, so neither runs past the chart's edge and gets cut off.
public enum DateAxisLabels {
    public enum Alignment: Sendable, Hashable {
        case center
        /// Text ends at the bar's middle (the rightmost label).
        case trailing
        /// Text starts at the bar's middle (a label on the leftmost bar).
        case leading
    }

    public struct Mark: Sendable, Hashable {
        /// The middle of the labeled bar.
        public var date: Date
        public var alignment: Alignment
    }

    /// Bars between labels: every 4 hours, every day for 7 d, every other day for 14 d, and every
    /// 5 days for 30 d.
    public static func step(for range: InsightsRange) -> Int {
        switch range {
        case .day: 4
        case .week: 1
        case .twoWeeks: 2
        case .month: 5
        }
    }

    /// Marks for bars starting at `starts` (oldest first), oldest mark first.
    public static func marks(
        bucketStarts starts: [Date],
        range: InsightsRange,
        calendar: Calendar = .current
    ) -> [Mark] {
        guard !starts.isEmpty else { return [] }
        let unit: Calendar.Component = range == .day ? .hour : .day
        let step = step(for: range)
        let last = starts.count - 1
        return stride(from: last, through: 0, by: -step).reversed().map { index in
            let start = starts[index]
            let end = calendar.date(byAdding: unit, value: 1, to: start) ?? start
            let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            let alignment: Alignment = index == last && last > 0 ? .trailing : (index == 0 && last > 0 ? .leading : .center)
            return Mark(date: middle, alignment: alignment)
        }
    }
}
