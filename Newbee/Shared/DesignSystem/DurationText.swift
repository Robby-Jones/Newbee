import Foundation

/// Formats derived durations for display. Durations always come from `SessionSnapshot`.
enum DurationText {
    /// Stopwatch style: "0:07", "12:05", "1:02:03".
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%ld:%02ld:%02ld", hours, minutes, seconds)
        }
        return String(format: "%ld:%02ld", minutes, seconds)
    }

    /// Compact summary: "<1 min", "21 min", "1 h", "1 h 5 min".
    static func short(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        if minutes < 1 { return String(localized: "<1 min") }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        if rest == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(rest) min")
    }

    /// VoiceOver, minute granularity so it isn't re-announced every second: "12 minutes".
    static func spoken(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        if minutes < 1 { return String(localized: "less than a minute") }
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
