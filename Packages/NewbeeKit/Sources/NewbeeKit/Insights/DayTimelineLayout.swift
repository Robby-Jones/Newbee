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
