import Foundation

/// Formats derived durations for display. Durations always come from `SessionSnapshot`.
///
/// Negative, NaN and infinite values read as zero, and absurdly long ones are capped, rather
/// than trapping in `Int(_:)`.
enum DurationText {
    /// About 31 years: far beyond any real feed or gap, well inside `Int`.
    static let longest: TimeInterval = 1_000_000_000

    /// `interval` clamped to 0...`longest`; 0 when it isn't a number.
    static func sanitized(_ interval: TimeInterval) -> TimeInterval {
        interval.isFinite ? min(max(0, interval), longest) : 0
    }

    /// Stopwatch style: "0:07", "12:05", "1:02:03".
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(sanitized(interval).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%ld:%02ld:%02ld", hours, minutes, seconds)
        }
        return String(format: "%ld:%02ld", minutes, seconds)
    }

    /// Compact summary: "0 min" (nothing at all, such as an unused side), "<1 min", "21 min",
    /// "1 h", "1 h 5 min".
    static func short(_ interval: TimeInterval) -> String {
        let interval = sanitized(interval)
        if interval < 1 { return String(localized: "0 min") }
        let minutes = Int(interval / 60)
        if minutes < 1 { return String(localized: "<1 min") }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        if rest == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(rest) min")
    }

    /// Time since the last feed: like `short` under a day ("2 h 14 min"), then with days in
    /// front ("1 d 2 h 5 min"). Parts that are zero are left out, as in `short` ("2 d 3 h").
    static func sinceLastFeed(_ interval: TimeInterval) -> String {
        let interval = sanitized(interval)
        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (24 * 60)
        guard days > 0 else { return short(interval) }
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        var parts = [String(localized: "\(days) d")]
        if hours > 0 { parts.append(String(localized: "\(hours) h")) }
        if minutes > 0 { parts.append(String(localized: "\(minutes) min")) }
        return parts.joined(separator: " ")
    }

    /// VoiceOver, minute granularity so it isn't re-announced every second: "12 minutes".
    static func spoken(_ interval: TimeInterval) -> String {
        let interval = sanitized(interval)
        if interval < 1 { return String(localized: "0 minutes") }
        let minutes = Int(interval / 60)
        if minutes < 1 { return String(localized: "less than a minute") }
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .wide))
    }
}
