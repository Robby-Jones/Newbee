import Foundation
import NewbeeKit
import SwiftData

/// `FeedingRepository` backed by SwiftData (docs/TIMER_ENGINE.md §4).
///
/// Every read fetches from the context; every write commits with `save()` before returning, and
/// rolls the context back if the commit fails, so the store holds either the old or the new state.
@MainActor
final class SwiftDataFeedingRepository: FeedingRepository {
    /// Held so the container lives as long as the repository: SwiftData traps if a context is
    /// used after its container has been deallocated.
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    func openSessions() throws -> [SessionSnapshot] {
        let breast = FeedingKind.breast.rawValue
        let active = SessionStatus.active.rawValue
        let paused = SessionStatus.paused.rawValue
        let descriptor = FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.kindRaw == breast && ($0.statusRaw == active || $0.statusRaw == paused) },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.sessionSnapshot)
    }

    func session(id: UUID) throws -> SessionSnapshot? {
        try model(id: id)?.sessionSnapshot
    }

    func recentCompletedSessions(limit: Int) throws -> [SessionSnapshot] {
        let breast = FeedingKind.breast.rawValue
        let completed = SessionStatus.completed.rawValue
        var descriptor = FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.kindRaw == breast && $0.statusRaw == completed },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(\.sessionSnapshot)
    }

    func save(_ snapshots: [SessionSnapshot], modifiedAt: Date) throws {
        do {
            for snapshot in snapshots {
                let session: FeedingSession
                if let existing = try model(id: snapshot.id) {
                    session = existing
                } else {
                    session = FeedingSession(
                        id: snapshot.id,
                        kind: .breast,
                        status: snapshot.status,
                        startedAt: snapshot.startedAt,
                        timeZoneID: snapshot.timeZoneID,
                        source: snapshot.source
                    )
                    session.createdAt = modifiedAt
                    context.insert(session)
                    session.baby = try defaultBaby()
                }
                session.apply(snapshot, in: context)
                session.modifiedAt = modifiedAt
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(sessionID: UUID) throws {
        guard let session = try model(id: sessionID) else { return }
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
        var descriptor = FetchDescriptor<FeedingSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Single-baby MVP: new sessions belong to the first baby profile, if one exists.
    private func defaultBaby() throws -> Baby? {
        var descriptor = FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// Stands in when the store could not be opened. Every call fails, so commands (including ones
/// from Live Activity buttons) report an error instead of pretending to save.
@MainActor
final class UnavailableFeedingRepository: FeedingRepository {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func openSessions() throws -> [SessionSnapshot] { throw PersistenceError.storeUnavailable(reason) }
    func session(id: UUID) throws -> SessionSnapshot? { throw PersistenceError.storeUnavailable(reason) }
    func recentCompletedSessions(limit: Int) throws -> [SessionSnapshot] { throw PersistenceError.storeUnavailable(reason) }
    func save(_ snapshots: [SessionSnapshot], modifiedAt: Date) throws { throw PersistenceError.storeUnavailable(reason) }
    func delete(sessionID: UUID) throws { throw PersistenceError.storeUnavailable(reason) }
}
