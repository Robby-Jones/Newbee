import Foundation

/// Storage for bottle feeds, in terms of `BottleEntry` values.
///
/// The app implements it with SwiftData (`SwiftDataBottleRepository`, which stores each entry as a
/// completed `FeedingSession` of kind `bottle`); `InMemoryBottleRepository` serves tests and previews.
@MainActor
public protocol BottleRepository: AnyObject {
    /// One entry by ID.
    func bottle(id: UUID) throws -> BottleEntry?

    /// The newest entries by `startedAt`, newest first.
    func recentBottles(limit: Int) throws -> [BottleEntry]

    /// Entries that started in `[interval.start, interval.end)`, oldest first.
    func bottles(startingIn interval: DateInterval) throws -> [BottleEntry]

    /// Inserts or replaces the entry and commits.
    func save(_ entry: BottleEntry, modifiedAt: Date) throws

    /// Deletes an entry. Deleting a missing entry is not an error.
    func deleteBottle(id: UUID) throws
}

/// A dictionary-backed repository for tests and SwiftUI previews.
@MainActor
public final class InMemoryBottleRepository: BottleRepository {
    public private(set) var entries: [UUID: BottleEntry]
    /// When set, every save and delete throws this error and changes nothing.
    public var simulatedFailure: (any Error)?

    public init(entries: [BottleEntry] = []) {
        self.entries = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    }

    public func bottle(id: UUID) throws -> BottleEntry? {
        entries[id]
    }

    public func recentBottles(limit: Int) throws -> [BottleEntry] {
        Array(entries.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    public func bottles(startingIn interval: DateInterval) throws -> [BottleEntry] {
        entries.values
            .filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public func save(_ entry: BottleEntry, modifiedAt: Date) throws {
        if let simulatedFailure { throw simulatedFailure }
        entries[entry.id] = entry
    }

    public func deleteBottle(id: UUID) throws {
        if let simulatedFailure { throw simulatedFailure }
        entries[id] = nil
    }
}
