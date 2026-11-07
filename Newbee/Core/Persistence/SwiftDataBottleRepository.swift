import Foundation
import NewbeeKit
import SwiftData

/// `BottleRepository` backed by SwiftData. Each entry is a completed `FeedingSession` of kind
/// `bottle` with `BottleDetails` and no segments (docs/DATA_MODEL.md, invariant 5).
///
/// Every write commits before returning and rolls the context back if the commit fails.
@MainActor
final class SwiftDataBottleRepository: BottleRepository {
    /// Held so the container outlives the context (see `SwiftDataFeedingRepository`).
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    func bottle(id: UUID) throws -> BottleEntry? {
        try model(id: id)?.bottleEntry
    }

    func recentBottles(limit: Int) throws -> [BottleEntry] {
        let bottle = FeedingKind.bottle.rawValue
        var descriptor = FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.kindRaw == bottle },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).compactMap(\.bottleEntry)
    }

    func bottles(startingIn interval: DateInterval) throws -> [BottleEntry] {
        let bottle = FeedingKind.bottle.rawValue
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.kindRaw == bottle && $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor).compactMap(\.bottleEntry)
    }

    func save(_ entry: BottleEntry, modifiedAt: Date) throws {
        do {
            let session: FeedingSession
            if let existing = try model(id: entry.id) {
                session = existing
            } else {
                session = FeedingSession(
                    id: entry.id,
                    kind: .bottle,
                    status: .completed,
                    startedAt: entry.startedAt,
                    timeZoneID: entry.timeZoneID,
                    source: .manual
                )
                session.createdAt = modifiedAt
                context.insert(session)
                session.baby = try defaultBaby()
            }
            session.apply(entry, in: context)
            session.modifiedAt = modifiedAt
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteBottle(id: UUID) throws {
        guard let session = try model(id: id) else { return }
        session.deleteWithChildren(from: context)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Helpers

    private func model(id: UUID) throws -> FeedingSession? {
        let bottle = FeedingKind.bottle.rawValue
        var descriptor = FetchDescriptor<FeedingSession>(predicate: #Predicate { $0.id == id && $0.kindRaw == bottle })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Single-baby MVP: new entries belong to the first baby profile, if one exists.
    private func defaultBaby() throws -> Baby? {
        var descriptor = FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// Stands in when the store could not be opened: every call fails instead of pretending to save.
@MainActor
final class UnavailableBottleRepository: BottleRepository {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func bottle(id: UUID) throws -> BottleEntry? { throw PersistenceError.storeUnavailable(reason) }
    func recentBottles(limit: Int) throws -> [BottleEntry] { throw PersistenceError.storeUnavailable(reason) }
    func bottles(startingIn interval: DateInterval) throws -> [BottleEntry] { throw PersistenceError.storeUnavailable(reason) }
    func save(_ entry: BottleEntry, modifiedAt: Date) throws { throw PersistenceError.storeUnavailable(reason) }
    func deleteBottle(id: UUID) throws { throw PersistenceError.storeUnavailable(reason) }
}

// MARK: - Mapping

extension FeedingSession {
    /// A value copy of this bottle feed, or `nil` if this isn't a bottle session with details.
    var bottleEntry: BottleEntry? {
        guard kind == .bottle, let bottle else { return nil }
        return BottleEntry(
            id: id,
            startedAt: startedAt,
            contents: bottle.contents,
            amountML: bottle.amountML,
            enteredUnit: bottle.enteredUnit,
            durationSeconds: bottle.durationSeconds,
            notes: notes,
            timeZoneID: timeZoneID
        )
    }

    /// Makes this bottle session match `entry`, creating its `BottleDetails` if needed.
    func apply(_ entry: BottleEntry, in context: ModelContext) {
        kind = .bottle
        status = .completed
        startedAt = entry.startedAt
        endedAt = entry.endedAt
        timeZoneID = entry.timeZoneID
        notes = entry.notes
        revision += 1
        if let bottle {
            bottle.contents = entry.contents
            bottle.amountML = entry.amountML
            bottle.enteredUnit = entry.enteredUnit
            bottle.durationSeconds = entry.durationSeconds
        } else {
            let details = BottleDetails(
                contents: entry.contents,
                amountML: entry.amountML,
                enteredUnit: entry.enteredUnit,
                durationSeconds: entry.durationSeconds
            )
            context.insert(details)
            bottle = details
        }
    }
}
