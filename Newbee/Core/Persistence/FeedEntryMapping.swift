import Foundation
import NewbeeKit
import SwiftData

// Maps stored sessions of every kind to `FeedEntry`, the value History and Home work with.

extension FeedingSession {
    /// This finished feed as a `FeedEntry`, or `nil` while it is still running (or for kinds the
    /// app doesn't show yet).
    var feedEntry: FeedEntry? {
        guard status == .completed else { return nil }
        switch kind {
        case .breast:
            return FeedEntry(breast: sessionSnapshot)
        case .bottle:
            return FeedEntry(
                id: id,
                start: startedAt,
                end: endedAt,
                details: .bottle(BottleSummary(
                    contents: bottle?.contents ?? .other,
                    amountML: bottle?.amountML ?? 0,
                    enteredUnit: bottle?.enteredUnit ?? .milliliters
                )),
                notes: notes,
                needsReview: needsReview,
                source: source
            )
        case .pump, .combo:
            return nil
        }
    }

    /// Finished feeds of every kind, newest first. `limit` keeps Home's query small.
    static func completedFeeds(limit: Int? = nil) -> FetchDescriptor<FeedingSession> {
        let completed = SessionStatus.completed.rawValue
        var descriptor = FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.statusRaw == completed },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}

/// A complete value copy of a bottle feed, kept so deleting one from History can be undone.
struct BottleFeedRecord: Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var timeZoneID: String
    var notes: String
    var source: EntrySource
    var needsReview: Bool
    var revision: Int
    var createdAt: Date
    var contents: BottleContents
    var amountML: Double
    var enteredUnit: VolumeUnit
    var durationSeconds: Double?
}

/// Deletes and restores bottle feeds for History. Breastfeeds go through `FeedingSessionManager`
/// instead, so "last side" and reminders stay in step.
@MainActor
protocol BottleFeedDeleting: AnyObject {
    /// Deletes the bottle feed and returns a copy for undo.
    func deleteBottleFeed(id: UUID) throws -> BottleFeedRecord
    /// Re-inserts a deleted bottle feed exactly as it was.
    func restoreBottleFeed(_ record: BottleFeedRecord) throws
}

enum BottleFeedError: LocalizedError {
    case notFound

    var errorDescription: String? { "That feeding no longer exists." }
}

@MainActor
final class SwiftDataBottleFeedDeleter: BottleFeedDeleting {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    func deleteBottleFeed(id: UUID) throws -> BottleFeedRecord {
        let bottleKind = FeedingKind.bottle.rawValue
        var descriptor = FetchDescriptor<FeedingSession>(predicate: #Predicate { $0.id == id && $0.kindRaw == bottleKind })
        descriptor.fetchLimit = 1
        guard let session = try context.fetch(descriptor).first else { throw BottleFeedError.notFound }
        let record = BottleFeedRecord(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            timeZoneID: session.timeZoneID,
            notes: session.notes,
            source: session.source,
            needsReview: session.needsReview,
            revision: session.revision,
            createdAt: session.createdAt,
            contents: session.bottle?.contents ?? .other,
            amountML: session.bottle?.amountML ?? 0,
            enteredUnit: session.bottle?.enteredUnit ?? .milliliters,
            durationSeconds: session.bottle?.durationSeconds
        )
        session.deleteWithChildren(from: context)
        try commit()
        return record
    }

    func restoreBottleFeed(_ record: BottleFeedRecord) throws {
        let session = FeedingSession(
            id: record.id,
            kind: .bottle,
            status: .completed,
            startedAt: record.startedAt,
            timeZoneID: record.timeZoneID,
            source: record.source
        )
        session.endedAt = record.endedAt
        session.notes = record.notes
        session.needsReview = record.needsReview
        session.revision = record.revision + 1
        session.createdAt = record.createdAt
        session.modifiedAt = .now
        context.insert(session)
        let details = BottleDetails(
            contents: record.contents,
            amountML: record.amountML,
            enteredUnit: record.enteredUnit,
            durationSeconds: record.durationSeconds
        )
        context.insert(details)
        session.bottle = details
        var babies = FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.createdAt)])
        babies.fetchLimit = 1
        session.baby = try context.fetch(babies).first
        try commit()
    }

    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
