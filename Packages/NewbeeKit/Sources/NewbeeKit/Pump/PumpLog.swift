import Foundation

/// Logs, edits and deletes pumping sessions, with validation and undo.
///
/// Like bottles, pumping sessions are entered by hand after the fact, so they don't go through
/// `FeedingSessionManager` and never affect the breastfeeding timer, its Live Activity, feed
/// reminders or the suggested next side.
@MainActor
public final class PumpLog {
    /// The result of a save, with what's needed to undo it.
    public struct SaveResult: Sendable, Hashable {
        public var saved: PumpEntry
        /// The entry as it was before an edit; `nil` when the save created a new entry.
        public var previous: PumpEntry?
    }

    /// Duration a new entry starts with when there's no earlier session to copy.
    public static let defaultDuration: TimeInterval = 15 * 60

    public let clock: any AppClock
    public let rules: PumpRules
    private let repository: any PumpRepository

    public init(repository: any PumpRepository, clock: any AppClock, rules: PumpRules = PumpRules()) {
        self.repository = repository
        self.clock = clock
        self.rules = rules
    }

    // MARK: - Drafts

    /// A new entry that just finished, pre-filled from the last session (same amounts and
    /// duration, shown in `unit`) so a routine session is one tap on Save. With no history:
    /// 60 mL (2 oz) a side for 15 minutes.
    ///
    /// The start is set back by the duration so the session ends now: people log pumping after
    /// they're done.
    public func newDraft(unit: VolumeUnit) -> PumpDraft {
        let now = clock.now
        let last = try? repository.recentPumps(limit: 1).first
        let fallback = BottlePresets.defaults(for: unit)[0]
        let left = last.map { BottleAmount(milliliters: $0.leftML).converted(to: unit) } ?? fallback
        let right = last.map { BottleAmount(milliliters: $0.rightML).converted(to: unit) } ?? fallback
        let duration = last.map { $0.durationSeconds ?? Self.defaultDuration } ?? Self.defaultDuration
        return PumpDraft(
            left: left,
            right: right,
            startedAt: now.addingTimeInterval(-duration),
            durationSeconds: duration,
            timeZoneID: TimeZone.current.identifier
        )
    }

    /// A draft for editing the entry with `id`, or `nil` if it no longer exists.
    public func editDraft(id: UUID) throws -> PumpDraft? {
        try repository.pump(id: id).map(PumpDraft.init(editing:))
    }

    public func problems(with draft: PumpDraft) -> [PumpValidationError] {
        rules.problems(with: draft, now: clock.now)
    }

    // MARK: - Commands

    /// Validates and saves `draft` as a new entry, or over the entry it edits.
    @discardableResult
    public func save(_ draft: PumpDraft) throws -> SaveResult {
        let now = clock.now
        let entry = try rules.entry(from: draft, now: now)
        let previous = try draft.id.flatMap { try repository.pump(id: $0) }
        try repository.save(entry, modifiedAt: now)
        return SaveResult(saved: entry, previous: previous)
    }

    /// Deletes the entry and returns it, so it can be restored for undo.
    @discardableResult
    public func delete(id: UUID) throws -> PumpEntry? {
        guard let entry = try repository.pump(id: id) else { return nil }
        try repository.deletePump(id: id)
        return entry
    }

    /// Writes an entry back exactly as it was (undo of a delete or an edit). Not re-validated:
    /// it was valid when first saved.
    public func restore(_ entry: PumpEntry) throws {
        try repository.save(entry, modifiedAt: clock.now)
    }

    /// Reverses a save: deletes a new entry, or puts back the pre-edit version.
    public func undo(_ result: SaveResult) throws {
        if let previous = result.previous {
            try restore(previous)
        } else {
            try repository.deletePump(id: result.saved.id)
        }
    }

    // MARK: - Queries

    public func recent(limit: Int) throws -> [PumpEntry] {
        try repository.recentPumps(limit: limit)
    }

    /// Sessions that started on the calendar day containing `date`.
    public func summary(forDayContaining date: Date, calendar: Calendar = .current) throws -> PumpSummary {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return PumpSummary(entries: [])
        }
        return PumpSummary(entries: try repository.pumps(startingIn: DateInterval(start: start, end: end)))
    }
}

/// Totals for a set of pumping sessions, such as one day's.
public struct PumpSummary: Sendable, Hashable {
    public var count: Int
    public var leftML: Double
    public var rightML: Double
    /// Pumping time for sessions that recorded a duration.
    public var duration: TimeInterval

    public init(entries: [PumpEntry]) {
        count = entries.count
        leftML = entries.reduce(0) { $0 + $1.leftML }
        rightML = entries.reduce(0) { $0 + $1.rightML }
        duration = entries.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    public var totalML: Double { leftML + rightML }

    public var isEmpty: Bool { count == 0 }
}
