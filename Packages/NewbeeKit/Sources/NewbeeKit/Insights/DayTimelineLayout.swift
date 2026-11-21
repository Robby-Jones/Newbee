import Foundation

/// Where a feed sits in one day's column of the Calendar week view, as fractions of the
/// column's height from midnight (0) to the next midnight (1).
///
/// Positions follow the clock on the wall, like the column's hour axis, not the seconds since
/// midnight: on the 25-hour day clocks fall back, a feed at 23:30 must sit at 23:30 and not
/// below the column, and on the 23-hour spring-forward day a feed at 03:30 must sit at 03:30,
/// not an hour early. Both passes of the repeated hour share the same place on the axis.
public enum DayTimelineLayout {
    public struct Span: Sendable, Hashable {
        /// Distance from the top (midnight), 0...1.
        public var top: Double
        /// Height, 0...(1 - top). Clipped at midnight for an entry that runs into the next day.
        public var height: Double
    }

    /// `date`'s clock time on `day` as a fraction of the day: 0 at or before midnight, 1 at or
    /// after the next midnight.
    public static func position(of date: Date, onDay day: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: day)
        guard date > start else { return 0 }
        guard let next = calendar.date(byAdding: .day, value: 1, to: start), date < next else { return 1 }
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hours = Double(time.hour ?? 0)
        let minutes = Double(time.minute ?? 0)
        let wholeSeconds = Double(time.second ?? 0)
        let fraction = Double(time.nanosecond ?? 0) / 1_000_000_000
        let seconds: Double = hours * 3_600 + minutes * 60 + wholeSeconds + fraction
        return min(1, max(0, seconds / 86_400))
    }

    /// The block for an entry from `start` to `end` on `day`.
    public static func span(from start: Date, to end: Date, onDay day: Date, calendar: Calendar = .current) -> Span {
        let top = position(of: start, onDay: day, calendar: calendar)
        let bottom = position(of: max(start, end), onDay: day, calendar: calendar)
        var height = bottom - top
        if height < 0 {
            // Clocks fell back during the entry (01:50 EDT → 01:10 EST): its clock end is before
            // its clock start, so draw its real length instead.
            height = max(start, end).timeIntervalSince(start) / 86_400
        }
        return Span(top: top, height: min(max(0, height), 1 - top))
    }
}

extension DayTimelineLayout {
    /// Where a block sits across the day column: lane `index` of `count` equal-width lanes.
    public struct Lane: Sendable, Hashable {
        public var index: Int
        public var count: Int

        public init(index: Int, count: Int) {
            self.index = index
            self.count = count
        }
    }

    /// Side-by-side lanes for blocks that overlap in time, the way a calendar app shows clashing
    /// meetings: each block takes the leftmost lane free at its start, and every block in a run of
    /// overlapping blocks splits the width into as many lanes as that run needed.
    ///
    /// `minimumHeight` is the shortest a block is drawn (as a fraction of the day), so a bottle or
    /// a 2-minute feed that only overlaps once it's drawn still gets its own lane. Blocks that
    /// merely touch (one ends as the next starts) share a lane. Returns one lane per span, in the
    /// order given.
    public static func lanes(for spans: [Span], minimumHeight: Double = 0) -> [Lane] {
        let order = spans.indices.sorted { a, b in
            if spans[a].top != spans[b].top { return spans[a].top < spans[b].top }
            if spans[a].height != spans[b].height { return spans[a].height > spans[b].height }
            return a < b
        }
        func bottom(_ i: Int) -> Double { spans[i].top + max(spans[i].height, minimumHeight) }
        // About a millisecond: rounding never makes touching blocks overlap.
        let tolerance = 1e-8

        var result = [Lane](repeating: Lane(index: 0, count: 1), count: spans.count)
        var cluster: [Int] = []
        // The bottom of each lane's last block in the current run.
        var laneBottoms: [Double] = []
        var clusterBottom = -Double.infinity

        func closeCluster() {
            for i in cluster { result[i].count = laneBottoms.count }
            cluster = []
            laneBottoms = []
        }

        for i in order {
            let top = spans[i].top
            if top >= clusterBottom - tolerance { closeCluster() }
            if let free = laneBottoms.firstIndex(where: { $0 <= top + tolerance }) {
                laneBottoms[free] = bottom(i)
                result[i].index = free
            } else {
                laneBottoms.append(bottom(i))
                result[i].index = laneBottoms.count - 1
            }
            cluster.append(i)
            clusterBottom = cluster.count == 1 ? bottom(i) : max(clusterBottom, bottom(i))
        }
        closeCluster()
        return result
    }
}
