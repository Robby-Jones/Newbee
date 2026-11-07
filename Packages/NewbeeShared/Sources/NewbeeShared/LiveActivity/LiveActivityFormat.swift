import Foundation

/// Text for static (non-ticking) durations in the Live Activity. Kept in plain Swift so it is
/// identical in the app and the extension and can be unit tested on Linux.
public enum LiveActivityFormat {
    /// "0:07", "12:05", "1:02:03". Negative values show as zero; fractions are dropped.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 {
            return "\(h):\(pad(m)):\(pad(s))"
        }
        return "\(m):\(pad(s))"
    }

    /// Compact minutes for tight spaces: "0m", "12m", "1h 05m".
    public static func compact(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(pad(m))m" : "\(m)m"
    }

    /// VoiceOver text: "12 minutes 5 seconds", "1 hour 2 minutes", "0 seconds".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append(unit(h, "hour")) }
        if m > 0 { parts.append(unit(m, "minute")) }
        // Seconds are noise once a feed passes an hour.
        if s > 0 && h == 0 { parts.append(unit(s, "second")) }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds.rounded(.down))
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func unit(_ value: Int, _ name: String) -> String {
        "\(value) \(name)\(value == 1 ? "" : "s")"
    }
}
