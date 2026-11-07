import Foundation

/// One feed in the History timeline.
public struct TimelineRow: Sendable, Hashable, Identifiable {
    public var entry: FeedEntry
    /// Start-to-start time since the previous (earlier) feed in the same filtered list, shown as
    /// "2 h 40 min since previous". `nil` for the oldest feed.
    public var sincePrevious: TimeInterval?

    public var id: UUID { entry.id }
}

/// One day of the History timeline, newest feed first.
public struct TimelineDay: Sendable, Hashable, Identifiable {
    /// Midnight at the start of the day, in the calendar's time zone.
    public var day: Date
    public var rows: [TimelineRow]

    public var id: Date { day }
}

/// Groups feeds into the History timeline (docs/UX_SPEC.md §3.6).
public enum FeedTimeline {
    /// Days newest first, each with its feeds newest first. Gaps are measured within the filtered
    /// list, so with the Breast filter a gap is the time since the previous breastfeed.
    public static func days(
        from entries: [FeedEntry],
        filter: FeedFilter = .all,
        calendar: Calendar = .current
    ) -> [TimelineDay] {
        let ascending = entries.filter(filter.includes).sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
        var rows: [TimelineRow] = []
        rows.reserveCapacity(ascending.count)
        var previous: FeedEntry?
        for entry in ascending {
            rows.append(TimelineRow(entry: entry, sincePrevious: previous.map { entry.start.timeIntervalSince($0.start) }))
            previous = entry
        }

        var days: [TimelineDay] = []
        for row in rows.reversed() {
            let day = calendar.startOfDay(for: row.entry.start)
            if days.last?.day == day {
                days[days.count - 1].rows.append(row)
            } else {
                days.append(TimelineDay(day: day, rows: [row]))
            }
        }
        return days
    }
}
