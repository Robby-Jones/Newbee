import Foundation

/// CSV export of every finished feed, for sharing with a healthcare provider (docs/PRD.md #19).
///
/// One row per feed, oldest first. Times are local ("2026-11-07 02:15") in `timeZone`, with an
/// ISO 8601 column too so spreadsheets and scripts can both read it. Durations are in minutes
/// with one decimal; volumes in mL plus the amount as entered.
public enum FeedCSV {
    public static let header = [
        "start_local", "end_local", "start_iso8601", "type",
        "feeding_minutes", "left_minutes", "right_minutes", "first_side", "last_side",
        "bottle_contents", "amount_ml", "amount_entered", "entered_unit",
        "source", "needs_review", "notes",
    ]

    public static func make(_ entries: [FeedEntry], timeZone: TimeZone = .current) -> String {
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.calendar = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        local.dateFormat = "yyyy-MM-dd HH:mm"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = timeZone

        var lines = [header.joined(separator: ",")]
        for entry in entries.sorted(by: { $0.start < $1.start }) {
            var fields: [String] = [
                local.string(from: entry.start),
                entry.end.map(local.string(from:)) ?? "",
                iso.string(from: entry.start),
                entry.kind.rawValue,
            ]
            switch entry.details {
            case let .breast(left, right, first, last):
                fields += [minutes(left + right), minutes(left), minutes(right), first?.rawValue ?? "", last?.rawValue ?? "", "", "", "", ""]
            case let .bottle(bottle):
                let entered = bottle.enteredUnit.fromMilliliters(bottle.amountML)
                let duration = entry.end.map { $0.timeIntervalSince(entry.start) } ?? 0
                fields += [
                    duration > 0 ? minutes(duration) : "", "", "", "", "",
                    bottle.contents.rawValue,
                    number(bottle.amountML, digits: 0),
                    number(entered, digits: bottle.enteredUnit == .milliliters ? 0 : 1),
                    bottle.enteredUnit.rawValue,
                ]
            }
            fields += [entry.source.rawValue, entry.needsReview ? "yes" : "no", entry.notes]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        // CRLF per RFC 4180, which Excel and Numbers both expect.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// "Newbee feeds 2026-11-07.csv".
    public static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "Newbee feeds \(formatter.string(from: date)).csv"
    }

    static func escape(_ field: String) -> String {
        // Guard against spreadsheet formula injection from free-text notes.
        var value = field
        if let first = value.first, "=+-@".contains(first), Double(value) == nil {
            value = "'" + value
        }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        number(seconds / 60, digits: 1)
    }

    static func number(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
