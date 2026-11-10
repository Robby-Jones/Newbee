import Foundation

/// Reads the CSV that Huckleberry emails from "Export tracking data as CSV" (one file per child).
///
/// Huckleberry doesn't document the format. It was taken from a real export published by its
/// owner and from open-source readers of it:
///
///     "Type","Start","End","Duration","Start Condition","Start Location","End Condition","Notes"
///
/// - `Start`/`End`: "2024-07-16 13:07", local time with no offset (read in the phone's time zone).
/// - `Duration`: "00:14", hours and minutes.
/// - Bottle (`Type` Feed, `Start Location` Bottle): `Start Condition` "Formula", "Breast Milk" or
///   "Mixed"; `End Condition` the amount, "120ml" or "4.0oz".
/// - Nursing (`Type` Feed, `Start Location` Breast): time per side as "00:07R" and "00:06L" (right
///   in `Start Condition`, left in `End Condition`, either may be blank). The export doesn't say
///   which side came first.
/// - Pumping (`Type` Pump): `Start Condition` the left amount, `End Condition` the right amount.
///   Parents who log a total instead get one amount in `Start Condition` and a blank
///   `End Condition` ("3oz"); see `Options.unsidedPumpAmount`.
/// - Everything else (Sleep, Diaper, Growth, Solids, Meds, Tummy time, Bath, Potty…) has no place
///   in Newbee yet and is counted, not imported.
public enum HuckleberryCSV {
    public static let columns = ["Type", "Start", "End", "Duration", "Start Condition", "Start Location", "End Condition", "Notes"]

    public enum ParseError: Error, Sendable, Hashable {
        /// The file has no rows at all.
        case empty
        /// The header doesn't look like a Huckleberry export; lists the missing columns.
        case notHuckleberry(missingColumns: [String])
    }

    /// Choices for what the export leaves out.
    public struct Options: Sendable, Hashable {
        /// Where a pumping amount logged without a side goes.
        public enum UnsidedPump: Sendable, Hashable {
            /// Half on each side, so the total stays exact.
            case splitEvenly
            case allOn(Side)
        }

        /// The side placed first when a feed used both (the export has minutes per side, no order).
        public var firstSideWhenBoth: Side
        /// A pumping row with only one amount (`Start Condition`) is a total, not a left side.
        public var unsidedPumpAmount: UnsidedPump

        public init(firstSideWhenBoth: Side = .left, unsidedPumpAmount: UnsidedPump = .splitEvenly) {
            self.firstSideWhenBoth = firstSideWhenBoth
            self.unsidedPumpAmount = unsidedPumpAmount
        }
    }

    /// Parses `text`. Rows that can't be read are reported in `problems`, never guessed at.
    public static func parse(
        _ text: String,
        timeZone: TimeZone = .current,
        now: Date = Date(),
        options: Options = Options()
    ) throws(ParseError) -> HuckleberryExport {
        let table = CSVTable.parse(text)
        guard let header = table.first else { throw .empty }
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var index: [String: Int] = [:]
        for (position, name) in names.enumerated() where index[name] == nil {
            index[name] = position
        }
        let missing = columns.filter { index[$0.lowercased()] == nil }
        guard missing.isEmpty else { throw .notHuckleberry(missingColumns: missing) }

        let reader = RowReader(timeZone: timeZone, now: now, options: options)
        var export = HuckleberryExport()
        for (offset, fields) in table.dropFirst().enumerated() {
            // Line 1 is the header. (Notes with line breaks would shift this; it's only a hint.)
            let line = offset + 2
            let row = Row(fields: fields, index: index)
            guard !row.isBlank else { continue }
            export.rowCount += 1
            switch reader.read(row) {
            case .record(let record):
                export.records.append(record)
            case .unsupported(let type):
                export.unsupported[type, default: 0] += 1
            case .problem(let reason):
                export.problems.append(ImportProblem(line: line, type: row["Type"], start: row["Start"], reason: reason))
            }
        }
        return export
    }

    // MARK: - Rows

    struct Row {
        let fields: [String]
        let index: [String: Int]

        subscript(_ column: String) -> String {
            guard let position = index[column.lowercased()], position < fields.count else { return "" }
            return fields[position].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var isBlank: Bool {
            fields.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    enum Outcome {
        case record(ImportedRecord)
        case unsupported(String)
        case problem(ImportProblem.Reason)
    }

    struct RowReader {
        let timeZone: TimeZone
        let now: Date
        let options: Options
        let bottleRules = BottleRules()
        let pumpRules = PumpRules()

        func read(_ row: Row) -> Outcome {
            let type = row["Type"]
            switch type.lowercased() {
            case "feed":
                switch row["Start Location"].lowercased() {
                case "bottle": return bottle(row)
                case "breast": return breast(row)
                default: return .problem(.unknownFeedKind(row["Start Location"]))
                }
            case "pump":
                return pump(row)
            case "":
                return .problem(.missingType)
            default:
                return .unsupported(type)
            }
        }

        private func bottle(_ row: Row) -> Outcome {
            guard let start = HuckleberryCSV.date(row["Start"], in: timeZone) else { return .problem(.unreadableTime) }
            let contentsText = row["Start Condition"]
            let contents: BottleContents
            var notes = [String]()
            switch contentsText.lowercased() {
            case "formula": contents = .formula
            case "breast milk", "breastmilk": contents = .breastMilk
            case "mixed":
                contents = .other
                notes.append("Mixed breast milk and formula")
            case "":
                contents = .other
            default:
                contents = .other
                notes.append(contentsText)
            }
            guard let amount = HuckleberryCSV.amount(row["End Condition"]) else {
                return .problem(.unreadableAmount(row["End Condition"]))
            }
            notes.append(row["Notes"])
            let duration = HuckleberryCSV.duration(row["Duration"]).flatMap { $0 > 0 ? $0 : nil }
            let draft = BottleDraft(
                contents: contents,
                amount: amount,
                startedAt: start,
                durationSeconds: duration,
                notes: HuckleberryCSV.joinNotes(notes),
                timeZoneID: timeZone.identifier
            )
            do {
                return .record(.bottle(try bottleRules.entry(from: draft, now: now)))
            } catch {
                return .problem(.bottle(error))
            }
        }

        private func breast(_ row: Row) -> Outcome {
            guard let start = HuckleberryCSV.date(row["Start"], in: timeZone) else { return .problem(.unreadableTime) }
            var left: TimeInterval = 0
            var right: TimeInterval = 0
            var found = false
            for column in ["Start Condition", "End Condition"] {
                let text = row[column]
                guard !text.isEmpty else { continue }
                guard let (side, seconds) = HuckleberryCSV.sideDuration(text) else {
                    return .problem(.unreadableSideTime(text))
                }
                found = true
                if side == .left { left += seconds } else { right += seconds }
            }
            guard found, left + right > 0 else { return .problem(.noSideTimes) }
            let first: Side = left > 0 && right > 0 ? options.firstSideWhenBoth : (left > 0 ? .left : .right)
            var session = SimpleBreastEdit(start: start, firstSide: first, left: left, right: right)
                .newSession(notes: HuckleberryCSV.joinNotes([row["Notes"]]), timeZoneID: timeZone.identifier)
            session.source = .imported
            if left + right > Self.longestBreastfeed {
                return .problem(.breastfeedTooLong)
            }
            if !SessionValidator.isValid(session, now: now) {
                return .problem(.inFuture)
            }
            return .record(.breast(session))
        }

        private func pump(_ row: Row) -> Outcome {
            guard let start = HuckleberryCSV.date(row["Start"], in: timeZone) else { return .problem(.unreadableTime) }
            let leftText = row["Start Condition"]
            let rightText = row["End Condition"]
            let zero = BottleAmount(0, .milliliters)
            var left: BottleAmount
            var right: BottleAmount
            if leftText.isEmpty {
                left = zero
            } else if let amount = HuckleberryCSV.amount(leftText) {
                left = amount
            } else {
                return .problem(.unreadableAmount(leftText))
            }
            if rightText.isEmpty {
                right = zero
            } else if let amount = HuckleberryCSV.amount(rightText) {
                right = amount
            } else {
                return .problem(.unreadableAmount(rightText))
            }
            if !leftText.isEmpty, rightText.isEmpty {
                // One amount and no side: a total.
                switch options.unsidedPumpAmount {
                case .splitEvenly:
                    left = BottleAmount(left.value / 2, left.unit)
                    right = left
                case .allOn(.left):
                    right = BottleAmount(0, left.unit)
                case .allOn(.right):
                    right = left
                    left = BottleAmount(0, left.unit)
                }
            }
            // Both sides in the unit that was actually typed (a blank side has no unit).
            let unit = leftText.isEmpty ? right.unit : left.unit
            let duration = HuckleberryCSV.duration(row["Duration"]).flatMap { $0 > 0 ? $0 : nil }
            var draft = PumpDraft(
                left: BottleAmount(0, unit),
                right: BottleAmount(0, unit),
                startedAt: start,
                durationSeconds: duration,
                notes: HuckleberryCSV.joinNotes([row["Notes"]]),
                timeZoneID: timeZone.identifier
            )
            draft.setAmount(left, on: .left)
            draft.setAmount(right, on: .right)
            do {
                return .record(.pump(try pumpRules.entry(from: draft, now: now)))
            } catch {
                return .problem(.pump(error))
            }
        }

        /// Longer than any real feed; most likely a timer left running.
        static let longestBreastfeed: TimeInterval = 4 * 3600
    }

    // MARK: - Field formats

    /// "2024-07-16 13:07" (seconds allowed) in `timeZone`.
    static func date(_ text: String, in timeZone: TimeZone) -> Date? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "T" })
        guard parts.count == 2 else { return nil }
        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        let time = parts[1].split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, (2...3).contains(time.count),
              (1...12).contains(day[1]), (1...31).contains(day[2]),
              (0...23).contains(time[0]), (0...59).contains(time[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let second = time.count == 3 ? time[2] : 0
        guard (0...59).contains(second),
              let date = calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1], second: second)),
              // Rejects days a month doesn't have ("2024-02-30"). A local time skipped when
              // clocks spring forward still lands on the same day, a little later.
              calendar.component(.day, from: date) == day[2] else { return nil }
        return date
    }

    /// "00:14" → 840 seconds.
    static func duration(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              hours >= 0, (0..<60).contains(minutes) else { return nil }
        return TimeInterval(hours * 3600 + minutes * 60)
    }

    /// "00:07R" → (.right, 420).
    static func sideDuration(_ text: String) -> (Side, TimeInterval)? {
        guard let letter = text.last?.uppercased() else { return nil }
        let side: Side
        switch letter {
        case "L": side = .left
        case "R": side = .right
        default: return nil
        }
        guard let seconds = duration(String(text.dropLast()).trimmingCharacters(in: .whitespaces)) else { return nil }
        return (side, seconds)
    }

    /// "120ml", "4.0oz", "4,5 oz" → an amount in that unit. No unit means mL.
    static func amount(_ text: String) -> BottleAmount? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = trimmed.prefix { $0.isNumber || $0 == "." || $0 == "," }
        let unitText = trimmed.dropFirst(number.count).trimmingCharacters(in: .whitespaces).lowercased()
        guard let value = Double(number.replacingOccurrences(of: ",", with: ".")), value >= 0 else { return nil }
        switch unitText {
        case "", "ml": return BottleAmount(value, .milliliters)
        case "oz", "floz", "fl oz", "fl. oz": return BottleAmount(value, .fluidOunces)
        default: return nil
        }
    }

    static func joinNotes(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// What a Huckleberry file holds, before checking it against what Newbee already has.
public struct HuckleberryExport: Sendable, Hashable {
    /// Feeds and pumping sessions that can be imported, in file order.
    public var records: [ImportedRecord] = []
    /// Rows of types Newbee doesn't track, by their `Type` ("Sleep": 1977).
    public var unsupported: [String: Int] = [:]
    /// Feed and pumping rows that couldn't be read.
    public var problems: [ImportProblem] = []
    /// Non-blank rows after the header.
    public var rowCount = 0

    public init() {}

    public var unsupportedCount: Int { unsupported.values.reduce(0, +) }
}

/// A feed or pumping session read from another app's export.
public enum ImportedRecord: Sendable, Hashable {
    case breast(SessionSnapshot)
    case bottle(BottleEntry)
    case pump(PumpEntry)

    public var kind: FeedingKind {
        switch self {
        case .breast: .breast
        case .bottle: .bottle
        case .pump: .pump
        }
    }

    public var id: UUID {
        switch self {
        case .breast(let session): session.id
        case .bottle(let entry): entry.id
        case .pump(let entry): entry.id
        }
    }

    public var start: Date {
        switch self {
        case .breast(let session): session.startedAt
        case .bottle(let entry): entry.startedAt
        case .pump(let entry): entry.startedAt
        }
    }
}

/// A row that couldn't be imported, and why.
public struct ImportProblem: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        case missingType
        case unreadableTime
        /// A feed that's neither Bottle nor Breast.
        case unknownFeedKind(String)
        case unreadableAmount(String)
        case unreadableSideTime(String)
        /// A nursing row with no time on either side.
        case noSideTimes
        case breastfeedTooLong
        case inFuture
        case bottle(BottleValidationError)
        case pump(PumpValidationError)
    }

    /// Line in the file, counting the header as line 1.
    public var line: Int
    public var type: String
    /// The row's `Start` text, as written.
    public var start: String
    public var reason: Reason

    public init(line: Int, type: String, start: String, reason: Reason) {
        self.line = line
        self.type = type
        self.start = start
        self.reason = reason
    }
}
