import Foundation
import NewbeeKit
import SwiftData

/// `PumpRepository` backed by SwiftData. Each entry is a completed `FeedingSession` of kind
/// `pump` with `PumpDetails` and no segments (docs/DATA_MODEL.md).
///
/// Every write commits before returning and rolls the context back if the commit fails.
@MainActor
final class SwiftDataPumpRepository: PumpRepository {
    /// Held so the container outlives the context (see `SwiftDataFeedingRepository`).
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    func pump(id: UUID) throws -> PumpEntry? {
        try model(id: id)?.pumpEntry
    }

    func recentPumps(limit: Int) throws -> [PumpEntry] {
        let pump = FeedingKind.pump.rawValue
        var descriptor = FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.kindRaw == pump },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).compactMap(\.pumpEntry)
    }

    func pumps(startingIn interval: DateInterval) throws -> [PumpEntry] {
        let pump = FeedingKind.pump.rawValue
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.kindRaw == pump && $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor).compactMap(\.pumpEntry)
    }

    func save(_ entry: PumpEntry, modifiedAt: Date) throws {
        do {
            let session: FeedingSession
            if let existing = try model(id: entry.id) {
                session = existing
            } else {
                session = FeedingSession(
                    id: entry.id,
                    kind: .pump,
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

    func deletePump(id: UUID) throws {
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
        let pump = FeedingKind.pump.rawValue
        var descriptor = FetchDescriptor<FeedingSession>(predicate: #Predicate { $0.id == id && $0.kindRaw == pump })
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
final class UnavailablePumpRepository: PumpRepository {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func pump(id: UUID) throws -> PumpEntry? { throw PersistenceError.storeUnavailable(reason) }
    func recentPumps(limit: Int) throws -> [PumpEntry] { throw PersistenceError.storeUnavailable(reason) }
    func pumps(startingIn interval: DateInterval) throws -> [PumpEntry] { throw PersistenceError.storeUnavailable(reason) }
    func save(_ entry: PumpEntry, modifiedAt: Date) throws { throw PersistenceError.storeUnavailable(reason) }
    func deletePump(id: UUID) throws { throw PersistenceError.storeUnavailable(reason) }
}

// MARK: - Mapping

extension FeedingSession {
    /// A value copy of this pumping session, or `nil` if this isn't a pump session with details.
    var pumpEntry: PumpEntry? {
        guard kind == .pump, let pump else { return nil }
        return PumpEntry(
            id: id,
            startedAt: startedAt,
            leftML: pump.leftML,
            rightML: pump.rightML,
            enteredUnit: pump.enteredUnit,
            durationSeconds: pump.durationSeconds,
            notes: notes,
            timeZoneID: timeZoneID
        )
    }

    /// Makes this pump session match `entry`, creating its `PumpDetails` if needed.
    func apply(_ entry: PumpEntry, in context: ModelContext) {
        kind = .pump
        status = .completed
        startedAt = entry.startedAt
        endedAt = entry.endedAt
        timeZoneID = entry.timeZoneID
        notes = entry.notes
        revision += 1
        if let pump {
            pump.leftML = entry.leftML
            pump.rightML = entry.rightML
            pump.enteredUnit = entry.enteredUnit
            pump.durationSeconds = entry.durationSeconds
        } else {
            let details = PumpDetails(
                leftML: entry.leftML,
                rightML: entry.rightML,
                enteredUnit: entry.enteredUnit,
                durationSeconds: entry.durationSeconds
            )
            context.insert(details)
            pump = details
        }
    }

    /// Finished pumping sessions, newest first; optionally only those that started in
    /// `start ..< end`.
    static func completedPumps(from start: Date = .distantPast, to end: Date = .distantFuture) -> FetchDescriptor<FeedingSession> {
        let completed = SessionStatus.completed.rawValue
        let pump = FeedingKind.pump.rawValue
        return FetchDescriptor<FeedingSession>(
            predicate: #Predicate {
                $0.statusRaw == completed && $0.kindRaw == pump && $0.startedAt >= start && $0.startedAt < end
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }
}
