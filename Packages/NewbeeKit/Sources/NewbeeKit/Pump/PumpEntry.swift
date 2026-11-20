import Foundation

/// A logged pumping session, independent of persistence (docs/DATA_MODEL.md, `PumpDetails`).
///
/// Stored as a completed `FeedingSession` of kind `pump` with `PumpDetails` and no segments.
/// Pumping is not a feed: it never counts toward feed totals, gaps, reminders or the next side.
public struct PumpEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// When pumping started.
    public var startedAt: Date
    /// Canonical amounts in milliliters. Either side may be zero (one-sided pumping).
    public var leftML: Double
    public var rightML: Double
    /// The unit the parent typed, so editing shows their original entry.
    public var enteredUnit: VolumeUnit
    /// How long pumping took, if the parent entered it.
    public var durationSeconds: TimeInterval?
    public var notes: String
    /// IANA time zone identifier where the session was logged.
    public var timeZoneID: String
    /// Logged as one total, without a left/right split (Settings › "Log pumping as total only").
    /// The total is stored split evenly across `leftML` and `rightML`, so sums and older builds
    /// still work, but it's shown as "Total …" and the sides are never shown.
    public var isTotalOnly: Bool

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        leftML: Double,
        rightML: Double,
        enteredUnit: VolumeUnit = .milliliters,
        durationSeconds: TimeInterval? = nil,
        notes: String = "",
        timeZoneID: String = TimeZone.current.identifier,
        isTotalOnly: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.leftML = leftML
        self.rightML = rightML
        self.enteredUnit = enteredUnit
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.timeZoneID = timeZoneID
        self.isTotalOnly = isTotalOnly
    }

    /// A total-only entry for `totalML`, stored half on each side.
    public init(
        id: UUID = UUID(),
        startedAt: Date,
        totalML: Double,
        enteredUnit: VolumeUnit = .milliliters,
        durationSeconds: TimeInterval? = nil,
        notes: String = "",
        timeZoneID: String = TimeZone.current.identifier
    ) {
        self.init(
            id: id, startedAt: startedAt, leftML: totalML / 2, rightML: totalML / 2, enteredUnit: enteredUnit,
            durationSeconds: durationSeconds, notes: notes, timeZoneID: timeZoneID, isTotalOnly: true
        )
    }

    public var totalML: Double { leftML + rightML }

    /// End of the session: start plus duration, or the start itself when no duration was entered.
    public var endedAt: Date {
        startedAt.addingTimeInterval(durationSeconds ?? 0)
    }

    /// One side's amount in `unit` (default: the unit it was entered in).
    public func amount(on side: Side, in unit: VolumeUnit? = nil) -> BottleAmount {
        BottleAmount(milliliters: side == .left ? leftML : rightML).converted(to: unit ?? enteredUnit)
    }

    public var totalAmount: BottleAmount {
        totalAmount(in: enteredUnit)
    }

    /// Left plus right in `unit`.
    public func totalAmount(in unit: VolumeUnit) -> BottleAmount {
        BottleAmount(milliliters: totalML).converted(to: unit)
    }
}

/// What the Log Pumping sheet edits. Becomes a `PumpEntry` once it passes `PumpRules`.
/// Both sides are always in the same unit. A total-only draft keeps its total in `left` and
/// leaves `right` at zero; use `total` and `setTotal(_:)` for it.
public struct PumpDraft: Sendable, Hashable {
    /// Set when editing an existing entry; `nil` for a new one.
    public var id: UUID?
    public var left: BottleAmount
    public var right: BottleAmount
    public var startedAt: Date
    public var durationSeconds: TimeInterval?
    public var notes: String
    public var timeZoneID: String
    /// The stored amounts of the entry being edited, so saving it unchanged in another unit
    /// keeps the exact milliliters.
    public var originalLeftML: Double?
    public var originalRightML: Double?
    /// Asks for one total instead of left and right (see `PumpEntry.isTotalOnly`).
    public private(set) var isTotalOnly: Bool

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
        self.isTotalOnly = false
        self.left = left
        self.right = right.unit == left.unit ? right : right.converted(to: left.unit)
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.timeZoneID = timeZoneID
    }

    /// A total-only draft for `total`.
    public init(
        id: UUID? = nil,
        total: BottleAmount,
        startedAt: Date,
        durationSeconds: TimeInterval? = nil,
        notes: String = "",
        timeZoneID: String = TimeZone.current.identifier
    ) {
        self.init(
            id: id, left: total, right: BottleAmount(0, total.unit), startedAt: startedAt,
            durationSeconds: durationSeconds, notes: notes, timeZoneID: timeZoneID
        )
        isTotalOnly = true
    }

    /// A draft for editing `entry`, shown in `unit` (default: the unit it was entered in).
    /// A total-only entry stays total-only and an entry with sides keeps its sides.
    public init(editing entry: PumpEntry, unit: VolumeUnit? = nil) {
        if entry.isTotalOnly {
            self.init(
                id: entry.id,
                total: entry.totalAmount(in: unit ?? entry.enteredUnit),
                startedAt: entry.startedAt,
                durationSeconds: entry.durationSeconds,
                notes: entry.notes,
                timeZoneID: entry.timeZoneID
            )
            originalLeftML = entry.totalML
            return
        }
        self.init(
            id: entry.id,
            left: entry.amount(on: .left, in: unit),
            right: entry.amount(on: .right, in: unit),
            startedAt: entry.startedAt,
            durationSeconds: entry.durationSeconds,
            notes: entry.notes,
            timeZoneID: entry.timeZoneID
        )
        originalLeftML = entry.leftML
        originalRightML = entry.rightML
    }

    /// The milliliters that would be saved for `side`.
    public func milliliters(on side: Side) -> Double {
        side == .left
            ? left.milliliters(keeping: originalLeftML)
            : right.milliliters(keeping: originalRightML)
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
    /// Unchanged amounts convert from the stored values, so switching back and forth never drifts.
    public mutating func convert(to target: VolumeUnit) {
        guard target != unit else { return }
        let leftML = milliliters(on: .left)
        let rightML = milliliters(on: .right)
        left = left.value > 0 ? BottleAmount(milliliters: leftML).converted(to: target) : BottleAmount(0, target)
        right = right.value > 0 ? BottleAmount(milliliters: rightML).converted(to: target) : BottleAmount(0, target)
    }

    /// Left plus right, in the draft's unit (the entered total for a total-only draft).
    public var total: BottleAmount {
        isTotalOnly ? left : BottleAmount(unit.rounded(left.value + right.value), unit)
    }

    /// Sets a total-only draft's total.
    public mutating func setTotal(_ amount: BottleAmount) {
        setAmount(amount, on: .left)
    }

    /// The milliliters a total-only draft would save, or left plus right.
    public var totalMilliliters: Double {
        milliliters(on: .left) + (isTotalOnly ? 0 : milliliters(on: .right))
    }
}

/// Why a pumping draft can't be saved. Shown inline on the sheet.
public enum PumpValidationError: Error, Sendable, Hashable {
    case amountNotPositive
    case sideTooLarge(Side, maximumML: Double)
    /// A total-only entry over twice the per-side limit.
    case totalTooLarge(maximumML: Double)
    case startInFuture
    case durationNotPositive
    case durationTooLong(maximumSeconds: TimeInterval)
    case endInFuture
}

/// Validation rules for pumping sessions: something was pumped, each side at most 500 mL (a
/// total-only entry at most 1,000 mL),
/// no times in the future, and an optional duration of 1 minute to 2 hours.
public struct PumpRules: Sendable, Hashable {
    /// Largest amount accepted on one side, in milliliters.
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

    /// Largest total accepted for a total-only entry: both sides at their limit.
    public var maximumTotalML: Double { maximumPerSideML * 2 }

    /// Every problem with `draft`, most important first. Empty means it can be saved.
    public func problems(with draft: PumpDraft, now: Date) -> [PumpValidationError] {
        var problems: [PumpValidationError] = []
        let left = draft.milliliters(on: .left)
        let right = draft.milliliters(on: .right)
        if !(left >= 0 && right >= 0 && left + right > 0) {
            problems.append(.amountNotPositive)
        }
        if draft.isTotalOnly {
            if draft.totalMilliliters > maximumTotalML + 0.001 {
                problems.append(.totalTooLarge(maximumML: maximumTotalML))
            }
        } else {
            for side in Side.allCases where draft.milliliters(on: side) > maximumPerSideML + 0.001 {
                problems.append(.sideTooLarge(side, maximumML: maximumPerSideML))
            }
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
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isTotalOnly {
            return PumpEntry(
                id: draft.id ?? UUID(),
                startedAt: draft.startedAt,
                totalML: draft.totalMilliliters,
                enteredUnit: draft.unit,
                durationSeconds: draft.durationSeconds,
                notes: notes,
                timeZoneID: draft.timeZoneID
            )
        }
        return PumpEntry(
            id: draft.id ?? UUID(),
            startedAt: draft.startedAt,
            leftML: draft.milliliters(on: .left),
            rightML: draft.milliliters(on: .right),
            enteredUnit: draft.unit,
            durationSeconds: draft.durationSeconds,
            notes: notes,
            timeZoneID: draft.timeZoneID
        )
    }
}
