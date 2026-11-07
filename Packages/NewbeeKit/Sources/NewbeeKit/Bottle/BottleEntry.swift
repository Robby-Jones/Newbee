import Foundation

/// A logged bottle feed, independent of persistence (docs/DATA_MODEL.md, `BottleDetails`).
///
/// Stored as a completed `FeedingSession` of kind `bottle` with `BottleDetails` and no segments.
public struct BottleEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// When the bottle feed started (or happened, if no duration was entered).
    public var startedAt: Date
    public var contents: BottleContents
    /// Canonical amount in millilitres.
    public var amountML: Double
    /// The unit the parent typed, so editing shows their original entry.
    public var enteredUnit: VolumeUnit
    /// How long the feed took, if the parent entered it.
    public var durationSeconds: TimeInterval?
    public var notes: String
    /// IANA time zone identifier where the feed was logged.
    public var timeZoneID: String

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        contents: BottleContents,
        amountML: Double,
        enteredUnit: VolumeUnit = .milliliters,
        durationSeconds: TimeInterval? = nil,
        notes: String = "",
        timeZoneID: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.startedAt = startedAt
        self.contents = contents
        self.amountML = amountML
        self.enteredUnit = enteredUnit
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.timeZoneID = timeZoneID
    }

    /// End of the feed: start plus duration, or the start itself when no duration was entered.
    public var endedAt: Date {
        startedAt.addingTimeInterval(durationSeconds ?? 0)
    }

    /// The amount in the unit the parent entered it in.
    public var enteredAmount: BottleAmount {
        BottleAmount(milliliters: amountML).converted(to: enteredUnit)
    }
}

/// What the Log Bottle sheet edits. Becomes a `BottleEntry` once it passes `BottleRules`.
public struct BottleDraft: Sendable, Hashable {
    /// Set when editing an existing entry; `nil` for a new one.
    public var id: UUID?
    public var contents: BottleContents
    public var amount: BottleAmount
    public var startedAt: Date
    public var durationSeconds: TimeInterval?
    public var notes: String
    public var timeZoneID: String

    public init(
        id: UUID? = nil,
        contents: BottleContents,
        amount: BottleAmount,
        startedAt: Date,
        durationSeconds: TimeInterval? = nil,
        notes: String = "",
        timeZoneID: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.contents = contents
        self.amount = amount
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.timeZoneID = timeZoneID
    }

    /// A draft for editing `entry`, in the unit it was entered in.
    public init(editing entry: BottleEntry) {
        self.init(
            id: entry.id,
            contents: entry.contents,
            amount: entry.enteredAmount,
            startedAt: entry.startedAt,
            durationSeconds: entry.durationSeconds,
            notes: entry.notes,
            timeZoneID: entry.timeZoneID
        )
    }

    public var isEditing: Bool { id != nil }
}

/// Why a bottle draft can't be saved. Shown inline on the sheet.
public enum BottleValidationError: Error, Sendable, Hashable {
    case amountNotPositive
    case amountTooLarge(maximumML: Double)
    case startInFuture
    case durationNotPositive
    case durationTooLong(maximumSeconds: TimeInterval)
    case endInFuture
}

/// Validation rules for bottle feeds (docs/UX_SPEC.md §3.4: amount > 0 and ≤ 500 mL).
public struct BottleRules: Sendable, Hashable {
    /// Largest amount accepted, in millilitres.
    public var maximumML: Double
    /// Longest duration accepted.
    public var maximumDuration: TimeInterval
    /// How far ahead of now a time may be, to absorb the seconds between opening the sheet and
    /// saving and small clock differences.
    public var futureTolerance: TimeInterval

    public init(maximumML: Double = 500, maximumDuration: TimeInterval = 2 * 3600, futureTolerance: TimeInterval = 60) {
        self.maximumML = maximumML
        self.maximumDuration = maximumDuration
        self.futureTolerance = futureTolerance
    }

    /// Every problem with `draft`, most important first. Empty means it can be saved.
    public func problems(with draft: BottleDraft, now: Date) -> [BottleValidationError] {
        var problems: [BottleValidationError] = []
        let ml = draft.amount.milliliters
        if !(ml > 0) {
            problems.append(.amountNotPositive)
        } else if ml > maximumML + 0.001 {
            problems.append(.amountTooLarge(maximumML: maximumML))
        }
        let latest = now.addingTimeInterval(futureTolerance)
        if draft.startedAt > latest {
            problems.append(.startInFuture)
        }
        if let duration = draft.durationSeconds {
            if !(duration > 0) {
                problems.append(.durationNotPositive)
            } else if duration > maximumDuration {
                problems.append(.durationTooLong(maximumSeconds: maximumDuration))
            } else if draft.startedAt <= latest, draft.startedAt.addingTimeInterval(duration) > latest {
                problems.append(.endInFuture)
            }
        }
        return problems
    }

    /// The entry `draft` describes, or the first problem that prevents saving it.
    public func entry(from draft: BottleDraft, now: Date) throws(BottleValidationError) -> BottleEntry {
        if let problem = problems(with: draft, now: now).first {
            throw problem
        }
        return BottleEntry(
            id: draft.id ?? UUID(),
            startedAt: draft.startedAt,
            contents: draft.contents,
            amountML: draft.amount.milliliters,
            enteredUnit: draft.amount.unit,
            durationSeconds: draft.durationSeconds,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            timeZoneID: draft.timeZoneID
        )
    }
}
