import Foundation
import NewbeeKit
import SwiftData

extension FeedingSession {
    /// Finished feeds that started in `start ..< end`, newest first. Calendar and Insights read
    /// only the dates they show, so a long history doesn't slow them down. Pumping is left out.
    static func completedFeeds(from start: Date, to end: Date) -> FetchDescriptor<FeedingSession> {
        let completed = SessionStatus.completed.rawValue
        let pump = FeedingKind.pump.rawValue
        return FetchDescriptor<FeedingSession>(
            predicate: #Predicate {
                $0.statusRaw == completed && $0.kindRaw != pump && $0.startedAt >= start && $0.startedAt < end
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    /// The first finished feed (or, with `pumps`, pumping session) ever logged: when tracking
    /// began, so Insights averages skip the days before it.
    static func firstCompleted(pumps: Bool) -> FetchDescriptor<FeedingSession> {
        let completed = SessionStatus.completed.rawValue
        let pump = FeedingKind.pump.rawValue
        let predicate: Predicate<FeedingSession> = if pumps {
            #Predicate<FeedingSession> { $0.statusRaw == completed && $0.kindRaw == pump }
        } else {
            #Predicate<FeedingSession> { $0.statusRaw == completed && $0.kindRaw != pump }
        }
        var descriptor = FetchDescriptor<FeedingSession>(predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .forward)])
        descriptor.fetchLimit = 1
        return descriptor
    }
}
