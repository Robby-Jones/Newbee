import Foundation

/// One row in History: a feed (with its gap to the previous feed) or a pumping session.
public enum HistoryItem: Sendable, Hashable, Identifiable {
    case feed(TimelineRow)
    case pump(PumpEntry)

    public var id: UUID {
        switch self {
        case .feed(let row): row.id
        case .pump(let entry): entry.id
        }
    }

    public var start: Date {
        switch self {
        case .feed(let row): row.entry.start
        case .pump(let entry): entry.startedAt
        }
    }
}

/// One day of History, newest item first.
public struct HistoryDay: Sendable, Hashable, Identifiable {
    /// Midnight at the start of the day, in the calendar's time zone.
    public var day: Date
    public var items: [HistoryItem]

    public var id: Date { day }
}

/// Merges feeds and pumping sessions into History's day-grouped list.
///
/// Feed gaps ("2 h after the previous feed") come from `FeedTimeline`, so they are measured
/// between feeds only: a pumping session in between doesn't shorten them.
public enum HistoryTimeline {
    public static func days(
        feeds: [FeedEntry],
        pumps: [PumpEntry],
        filter: FeedFilter = .all,
        calendar: Calendar = .current
    ) -> [HistoryDay] {
        var items = FeedTimeline.days(from: feeds, filter: filter, calendar: calendar)
            .flatMap(\.rows)
            .map(HistoryItem.feed)
        if filter.includesPumping {
            items += pumps.map(HistoryItem.pump)
        }
        items.sort { ($0.start, $0.id.uuidString) > ($1.start, $1.id.uuidString) }

        var days: [HistoryDay] = []
        for item in items {
            let day = calendar.startOfDay(for: item.start)
            if days.last?.day == day {
                days[days.count - 1].items.append(item)
            } else {
                days.append(HistoryDay(day: day, items: [item]))
            }
        }
        return days
    }
}
