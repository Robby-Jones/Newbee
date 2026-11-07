import Foundation
import NewbeeKit
import SwiftData

/// CSV export and "Delete all data" (docs/DATA_MODEL.md §"Deleting", docs/UX_SPEC.md §3.10).
extension AppDependencies {
    enum DataError: LocalizedError {
        case storeUnavailable

        var errorDescription: String? {
            String(localized: "Your feeding data isn't available right now.")
        }
    }

    /// Every finished feed as CSV, written to a temporary file named by today's date.
    func exportCSV() throws -> URL {
        guard let container = modelContainer else { throw DataError.storeUnavailable }
        let entries = try container.mainContext.fetch(FeedingSession.completedFeeds()).compactMap(\.feedEntry)
        let csv = FeedCSV.make(entries)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(FeedCSV.fileName(at: clock.now))
        try Data(csv.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Deletes every feed and the baby profile, ends any Live Activity, cancels every
    /// notification and resets preferences except appearance. Can't be undone.
    func deleteAllData() async throws {
        guard let container = modelContainer else { throw DataError.storeUnavailable }
        // A running feed goes through the manager first, so its Live Activity ends with it.
        if sessionManager.activeSession != nil {
            _ = try? sessionManager.discardActive()
        }
        let context = container.mainContext
        do {
            // Children explicitly: `.cascade` is unreliable on iOS 17.
            for session in try context.fetch(FetchDescriptor<FeedingSession>()) {
                session.deleteWithChildren(from: context)
            }
            // Anything orphaned by an earlier cascade failure.
            for segment in try context.fetch(FetchDescriptor<FeedingSegment>()) {
                context.delete(segment)
            }
            for bottle in try context.fetch(FetchDescriptor<BottleDetails>()) {
                context.delete(bottle)
            }
            for baby in try context.fetch(FetchDescriptor<Baby>()) {
                context.delete(baby)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        preferences.resetToDefaults()
        // Re-read the now empty store: ends every Live Activity and clears reminders.
        await sessionManager.reload()
        await reminders.removeAll()
    }
}
