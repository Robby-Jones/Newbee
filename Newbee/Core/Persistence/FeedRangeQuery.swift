import Foundation
import NewbeeKit
import SwiftData

extension FeedingSession {
    /// Finished feeds that started in `start ..< end`, newest first. Calendar and Insights read
    /// only the dates they show, so a long history doesn't slow them down.
    static func completedFeeds(from start: Date, to end: Date) -> FetchDescriptor<FeedingSession> {
        let completed = SessionStatus.completed.rawValue
        return FetchDescriptor<FeedingSession>(
            predicate: #Predicate { $0.statusRaw == completed && $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }
}
