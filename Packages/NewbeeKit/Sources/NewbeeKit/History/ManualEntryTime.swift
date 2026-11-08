import Foundation

/// When a new manual entry (bottle, pumping, or untimed breastfeed) should default to.
///
/// From History's calendar, adding a feed while another day is selected should land on that day:
/// the selected day at the current time of day, never later than `now`. Today, or no selection,
/// is just `now`.
public enum ManualEntryTime {
    public static func reference(onDay day: Date?, now: Date, calendar: Calendar = .current) -> Date {
        guard let day, !calendar.isDate(day, inSameDayAs: now) else { return now }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        let candidate = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
        return min(candidate, now)
    }
}
