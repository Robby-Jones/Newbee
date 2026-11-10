import Foundation

/// Logs, edits and deletes bottle feeds, with validation and undo.
///
/// Bottle feeds are instant entries rather than timed sessions, so they don't go through
/// `FeedingSessionManager` and never affect the breastfeeding timer. They do count as the last
/// feed: after a change, the app calls `FeedingSessionManager.bottlesDidChange()` so the Live
/// Activity's since-last-feed count follows the newest feed.
@MainActor
public final class BottleLog {
    /// The result of a save, with what's needed to undo it.
    public struct SaveResult: Sendable, Hashable {
        public var saved: BottleEntry
        /// The entry as it was before an edit; `nil` when the save created a new entry.
        public var previous: BottleEntry?
    }

    public let clock: any AppClock
    public let rules: BottleRules
    private let repository: any BottleRepository

    public init(repository: any BottleRepository, clock: any AppClock, rules: BottleRules = BottleRules()) {
        self.repository = repository
        self.clock = clock
        self.rules = rules
    }

    // MARK: - Drafts

    /// A new entry at `time` (default and latest: now), pre-filled from the last bottle (same contents and amount,
    /// shown in `unit`) so a repeat feed is one tap on Save. With no history: breast milk and the
    /// middle preset.
    /// `contents` is what the parent picked last time, when the app remembers it; otherwise the
    /// latest bottle's contents, then breast milk.
    public func newDraft(unit: VolumeUnit, contents: BottleContents? = nil, at time: Date? = nil) -> BottleDraft {
        let now = min(time ?? clock.now, clock.now)
        let last = try? repository.recentBottles(limit: 1).first
        let amount = last.map { BottleAmount(milliliters: $0.amountML).converted(to: unit) }
            ?? BottlePresets.defaults(for: unit)[1]
        return BottleDraft(
            contents: contents ?? last?.contents ?? .breastMilk,
            amount: amount,
            startedAt: now,
            timeZoneID: TimeZone.current.identifier
        )
    }

    /// A draft for editing the entry with `id`, shown in `unit` (default: the unit it was
    /// entered in), or `nil` if it no longer exists.
    public func editDraft(id: UUID, unit: VolumeUnit? = nil) throws -> BottleDraft? {
        try repository.bottle(id: id).map { BottleDraft(editing: $0, unit: unit) }
    }

    public func problems(with draft: BottleDraft) -> [BottleValidationError] {
        rules.problems(with: draft, now: clock.now)
    }

    // MARK: - Commands

    /// Validates and saves `draft` as a new entry, or over the entry it edits.
    @discardableResult
    public func save(_ draft: BottleDraft) throws -> SaveResult {
        let now = clock.now
        let entry = try rules.entry(from: draft, now: now)
        let previous = try draft.id.flatMap { try repository.bottle(id: $0) }
        try repository.save(entry, modifiedAt: now)
        return SaveResult(saved: entry, previous: previous)
    }

    /// Deletes the entry and returns it, so it can be restored for undo.
    @discardableResult
    public func delete(id: UUID) throws -> BottleEntry? {
        guard let entry = try repository.bottle(id: id) else { return nil }
        try repository.deleteBottle(id: id)
        return entry
    }

    /// Writes an entry back exactly as it was (undo of a delete or an edit). Not re-validated:
    /// it was valid when first saved.
    public func restore(_ entry: BottleEntry) throws {
        try repository.save(entry, modifiedAt: clock.now)
    }

    /// Reverses a save: deletes a new entry, or puts back the pre-edit version.
    public func undo(_ result: SaveResult) throws {
        if let previous = result.previous {
            try restore(previous)
        } else {
            try repository.deleteBottle(id: result.saved.id)
        }
    }

    // MARK: - Queries

    public func recent(limit: Int) throws -> [BottleEntry] {
        try repository.recentBottles(limit: limit)
    }

    /// Bottles that started on the calendar day containing `date`.
    public func summary(forDayContaining date: Date, calendar: Calendar = .current) throws -> BottleDaySummary {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return BottleDaySummary(entries: [])
        }
        return BottleDaySummary(entries: try repository.bottles(startingIn: DateInterval(start: start, end: end)))
    }
}

/// Totals for a set of bottle feeds, such as one day's.
public struct BottleDaySummary: Sendable, Hashable {
    public var count: Int
    public var totalML: Double
    public var mlByContents: [BottleContents: Double]

    public init(entries: [BottleEntry]) {
        count = entries.count
        totalML = entries.reduce(0) { $0 + $1.amountML }
        mlByContents = entries.reduce(into: [:]) { $0[$1.contents, default: 0] += $1.amountML }
    }

    public var isEmpty: Bool { count == 0 }
}
