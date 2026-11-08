import Foundation

/// Storage for pumping sessions, in terms of `PumpEntry` values.
///
/// The app implements it with SwiftData (`SwiftDataPumpRepository`, which stores each entry as a
/// completed `FeedingSession` of kind `pump`); `InMemoryPumpRepository` serves tests and previews.
@MainActor
public protocol PumpRepository: AnyObject {
    /// One entry by ID.
    func pump(id: UUID) throws -> PumpEntry?

    /// The newest entries by `startedAt`, newest first.
    func recentPumps(limit: Int) throws -> [PumpEntry]

    /// Entries that started in `[interval.start, interval.end)`, oldest first.
    func pumps(startingIn interval: DateInterval) throws -> [PumpEntry]

    /// Inserts or replaces the entry and commits.
    func save(_ entry: PumpEntry, modifiedAt: Date) throws

    /// Deletes an entry. Deleting a missing entry is not an error.
    func deletePump(id: UUID) throws
}

/// A dictionary-backed repository for tests and SwiftUI previews.
@MainActor
public final class InMemoryPumpRepository: PumpRepository {
    public private(set) var entries: [UUID: PumpEntry]
    /// When set, every save and delete throws this error and changes nothing.
    public var simulatedFailure: (any Error)?

    public init(entries: [PumpEntry] = []) {
        self.entries = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    }

    public func pump(id: UUID) throws -> PumpEntry? {
        entries[id]
    }

    public func recentPumps(limit: Int) throws -> [PumpEntry] {
        Array(entries.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    public func pumps(startingIn interval: DateInterval) throws -> [PumpEntry] {
        entries.values
            .filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public func save(_ entry: PumpEntry, modifiedAt: Date) throws {
        if let simulatedFailure { throw simulatedFailure }
        entries[entry.id] = entry
    }

    public func deletePump(id: UUID) throws {
        if let simulatedFailure { throw simulatedFailure }
        entries[id] = nil
    }
}
