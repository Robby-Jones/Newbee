import Foundation
import NewbeeKit
import SwiftData

/// CSV and PDF export and "Delete all data" (docs/DATA_MODEL.md §"Deleting", docs/UX_SPEC.md §3.10).
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

    /// The feeding report for `range` as a US Letter PDF in a temporary file named by its days:
    /// a summary page, then every feed and pumping session day by day (docs/PRD.md #21).
    func exportPDF(range: FeedReportRange) throws -> URL {
        guard let container = modelContainer else { throw DataError.storeUnavailable }
        let context = container.mainContext
        let interval = range.interval(now: clock.now)
        let feeds = try context.fetch(FeedingSession.completedFeeds(from: interval.start, to: interval.end)).compactMap(\.feedEntry)
        let pumps = try context.fetch(FeedingSession.completedPumps(from: interval.start, to: interval.end)).compactMap(\.pumpEntry)
        let report = FeedReport(feeds: feeds, pumps: pumps, interval: interval)

        var descriptor = FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        let baby = try context.fetch(descriptor).first
        let header = FeedReportPDF.Header(
            babyName: baby?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            age: baby?.birthDate.map { BabyAge.text(from: $0, now: clock.now) },
            volumeUnit: preferences.volumeUnit,
            generatedAt: clock.now
        )

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(FeedReport.fileName(for: interval))
        try? FileManager.default.removeItem(at: url)
        try FeedReportPDF.write(report, header: header, to: url)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return url
    }

    /// Deletes every feed and the baby profile (photo included), ends any Live Activity, cancels every
    /// notification and resets preferences except appearance. Can't be undone.
    func deleteAllData() async throws {
        guard let container = modelContainer else { throw DataError.storeUnavailable }
        // A running feed goes through the manager first, so its Live Activity ends with it.
        if sessionManager.activeSession != nil {
            _ = try? sessionManager.discardActive()
        }
        let context = container.mainContext
        do {
            // Children explicitly: `.cascade` proved unreliable (seen on iOS 17), so don't rely on it.
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
            for pump in try context.fetch(FetchDescriptor<PumpDetails>()) {
                context.delete(pump)
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
        babyPhoto.remove()
        // Re-read the now empty store: ends every Live Activity and clears reminders.
        await sessionManager.reload()
        await reminders.removeAll()
    }
}
