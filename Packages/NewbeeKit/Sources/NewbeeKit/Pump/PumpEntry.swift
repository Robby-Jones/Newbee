import Foundation

/// A logged pumping session, independent of persistence (docs/DATA_MODEL.md, `PumpDetails`).
///
/// Stored as a completed `FeedingSession` of kind `pump` with `PumpDetails` and no segments.
/// Pumping is not a feed: it never counts toward feed totals, gaps, reminders or the next side.
public struct PumpEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// When pumping started.
    public var startedAt: Date
    /// Canonical amounts in millilitres. Either side may be zero (one-sided pumping).
    public var leftML: Double
    public var rightML: Double
    /// The unit the parent typed, so editing shows their original entry.
    public var enteredUnit: VolumeUnit
    /// How long pumping took, if the parent entered it.
    public var durationSeconds: TimeInterval?
    public var notes: String
    /// IANA time zone identifier where the session was logged.
    public var timeZoneID: String

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        leftML: Double,
        rightML: Double,
        enteredUnit: VolumeUnit = .milliliters,
        durationSeconds: TimeInterval? = nil,
        notes: String = "",
        timeZoneID: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.startedAt = startedAt
        self.leftML = leftML
        self.rightML = rightML
        self.enteredUnit = enteredUnit
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.timeZoneID = timeZoneID
    }

    public var totalML: Double { leftML + rightML }

    /// End of the session: start plus duration, or the start itself when no duration was entered.
    public var endedAt: Date {
        startedAt.addingTimeInterval(durationSeconds ?? 0)
    }

    public func amount(on side: Side) -> BottleAmount {
        BottleAmount(milliliters: side == .left ? leftML : rightML).converted(to: enteredUnit)
    }

    public var totalAmount: BottleAmount {
        BottleAmount(milliliters: totalML).converted(to: enteredUnit)
    }
}

/// What the Log Pumping sheet edits. Becomes a `PumpEntry` once it passes `PumpRules`.
/// Both sides are always in the same unit.
public struct PumpDraft: Sendable, Hashable {
    /// Set when editing an existing entry; `nil` for a new one.
    public var id: UUID?
    public var left: BottleAmount
    public var right: BottleAmount
    public var startedAt: Date
    public var durationSeconds: TimeInterval?
    public var notes: String
    public var timeZoneID: String

    public init(
        id: UUID? = nil,
        left: BottleAmount,
        right: BottleAmount,
        startedAt: Date,
        durationSeconds: TimeInterval? = nil,
        notes: String = "",
        timeZoneID: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.left = left
        self.right = right.unit == left.unit ? right : right.converted(to: left.unit)
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.timeZoneID = timeZoneID
    }

    /// A draft for editing `entry`, in the unit it was entered in.
    public init(editing entry: PumpEntry) {
        self.init(
            id: entry.id,
            left: entry.amount(on: .left),
            right: entry.amount(on: .right),
            startedAt: entry.startedAt,
            durationSeconds: entry.durationSeconds,
            notes: entry.notes,
            timeZoneID: entry.timeZoneID
        )
    }

    public var isEditing: Bool { id != nil }

    public var unit: VolumeUnit { left.unit }

    public func amount(on side: Side) -> BottleAmount {
        side == .left ? left : right
    }

    public mutating func setAmount(_ amount: BottleAmount, on side: Side) {
        let value = amount.unit == unit ? amount : amount.converted(to: unit)
        if side == .left { left = value } else { right = value }
    }

    /// Switches both sides to `target`, converting non-zero amounts.
    public mutating func convert(to target: VolumeUnit) {
        guard target != unit else { return }
        left = left.value > 0 ? left.converted(to: target) : BottleAmount(0, target)
        right = right.value > 0 ? right.converted(to: target) : BottleAmount(0, target)
    }

    /// Left plus right, in the draft's unit.
    public var total: BottleAmount {
        BottleAmount(unit.rounded(left.value + right.value), unit)
    }
}

/// Why a pumping draft can't be saved. Shown inline on the sheet.
public enum PumpValidationError: Error, Sendable, Hashable {
    case amountNotPositive
    case sideTooLarge(Side, maximumML: Double)
    case startInFuture
    case durationNotPositive
    case durationTooLong(maximumSeconds: TimeInterval)
    case endInFuture
}

/// Validation rules for pumping sessions: something was pumped, each side at most 500 mL,
/// no times in the future, and an optional duration of 1 minute to 2 hours.
public struct PumpRules: Sendable, Hashable {
    /// Largest amount accepted on one side, in millilitres.
    public var maximumPerSideML: Double
    /// Longest duration accepted.
    public var maximumDuration: TimeInterval
    /// How far ahead of now a time may be (seconds between opening the sheet and saving).
    public var futureTolerance: TimeInterval

    public init(maximumPerSideML: Double = 500, maximumDuration: TimeInterval = 2 * 3600, futureTolerance: TimeInterval = 60) {
        self.maximumPerSideML = maximumPerSideML
        self.maximumDuration = maximumDuration
        self.futureTolerance = futureTolerance
    }

    /// Every problem with `draft`, most important first. Empty means it can be saved.
    public func problems(with draft: PumpDraft, now: Date) -> [PumpValidationError] {
        var problems: [PumpValidationError] = []
        let left = draft.left.milliliters
        let right = draft.right.milliliters
        if !(left >= 0 && right >= 0 && left + right > 0) {
            problems.append(.amountNotPositive)
        }
        for side in Side.allCases where draft.amount(on: side).milliliters > maximumPerSideML + 0.001 {
            problems.append(.sideTooLarge(side, maximumML: maximumPerSideML))
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
    public func entry(from draft: PumpDraft, now: Date) throws(PumpValidationError) -> PumpEntry {
        if let problem = problems(with: draft, now: now).first {
            throw problem
        }
        return PumpEntry(
            id: draft.id ?? UUID(),
            startedAt: draft.startedAt,
            leftML: draft.left.milliliters,
            rightML: draft.right.milliliters,
            enteredUnit: draft.unit,
            durationSeconds: draft.durationSeconds,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            timeZoneID: draft.timeZoneID
        )
    }
}
