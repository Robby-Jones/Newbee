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

    /// Finished feeds of every kind, newest first. `limit` keeps Home's query small. Pumping
    /// sessions aren't feeds and are left out (see `completedPumps`).
    static func completedFeeds(limit: Int? = nil) -> FetchDescriptor<FeedingSession> {
        let completed = SessionStatus.completed.rawValue
        let pump = FeedingKind.pump.rawValue
        var descriptor = FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.statusRaw == completed && $0.kindRaw != pump },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}
