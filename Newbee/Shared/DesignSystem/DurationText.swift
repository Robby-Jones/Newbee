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

    /// VoiceOver, minute granularity so it isn't re-announced every second: "12 minutes".
    static func spoken(_ interval: TimeInterval) -> String {
        let interval = sanitized(interval)
        if interval < 1 { return String(localized: "0 minutes") }
        let minutes = Int(interval / 60)
        if minutes < 1 { return String(localized: "less than a minute") }
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
