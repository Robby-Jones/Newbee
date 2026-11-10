import Foundation
import NewbeeKit
import SwiftData

/// Importing another app's export (Huckleberry) and undoing it (docs/UX_SPEC.md §3.10).
///
/// Imported feeds and pumping sessions are ordinary completed sessions with source `imported`,
/// so they show everywhere a typed-in entry would, and "Remove imported data" can find them.
extension AppDependencies {
    enum ImportError: LocalizedError {
        case unreadableFile
        case notHuckleberry

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                String(localized: "Newbee couldn't read that file. Choose the CSV file from Huckleberry's export email.")
            case .notHuckleberry:
                String(localized: "That file isn't a Huckleberry export. In Huckleberry, use \u{201C}Export tracking data as CSV\u{201D} and choose the file it emails you.")
            }
        }
    }

    /// Reads a Huckleberry export and works out what importing it would add. Saves nothing.
    func prepareHuckleberryImport(from url: URL) throws -> ImportPlan {
        guard let container = modelContainer else { throw DataError.storeUnavailable }
        let text = try Self.readText(at: url)
        let export: HuckleberryExport
        do {
            export = try HuckleberryCSV.parse(text, timeZone: .current, now: clock.now)
        } catch {
            throw ImportError.notHuckleberry
        }
        let existing = try container.mainContext.fetch(FetchDescriptor<FeedingSession>())
            .map { ImportKey(kind: $0.kind, start: $0.startedAt) }
        return ImportPlan(export: export, existing: existing)
    }

    /// Saves everything in `plan` in one go (all or nothing) and returns how many entries were added.
    @discardableResult
    func commitImport(_ plan: ImportPlan) async throws -> Int {
        guard let container = modelContainer else { throw DataError.storeUnavailable }
        guard !plan.isEmpty else { return 0 }
        let context = container.mainContext
        let now = clock.now
        do {
            var descriptor = FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.createdAt)])
            descriptor.fetchLimit = 1
            let baby = try context.fetch(descriptor).first
            for record in plan.records {
                let session = FeedingSession(
                    id: record.id,
                    kind: record.kind,
                    status: .completed,
                    startedAt: record.start,
                    source: .imported
                )
                session.createdAt = now
                context.insert(session)
                session.baby = baby
                switch record {
                case .breast(let snapshot):
                    session.apply(snapshot, in: context)
                case .bottle(let entry):
                    session.apply(entry, in: context)
                case .pump(let entry):
                    session.apply(entry, in: context)
                }
                session.modifiedAt = now
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        await feedDataDidChangeInBulk()
        return plan.records.count
    }

    /// How many imported feeds and pumping sessions the store holds.
    func importedEntryCount() -> Int {
        guard let context = modelContainer?.mainContext else { return 0 }
        return (try? context.fetchCount(FeedingSession.imported())) ?? 0
    }

    /// Deletes every imported entry, keeping everything logged in Newbee. Returns how many went.
    @discardableResult
    func removeImportedData() async throws -> Int {
        guard let container = modelContainer else { throw DataError.storeUnavailable }
        let context = container.mainContext
        let sessions = try context.fetch(FeedingSession.imported())
        guard !sessions.isEmpty else { return 0 }
        do {
            for session in sessions {
                session.deleteWithChildren(from: context)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        await feedDataDidChangeInBulk()
        return sessions.count
    }

    /// After many feeds change at once: re-read the last feed (Live Activity, next side) and
    /// plan reminders from it.
    private func feedDataDidChangeInBulk() async {
        await sessionManager.reload()
        await reminders.reschedule()
    }

    /// The file as text. Huckleberry writes UTF-8; UTF-16 and Windows Latin are accepted too, in
    /// case the file went through a spreadsheet app first.
    private static func readText(at url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadableFile
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        // A UTF-16 file starts with a byte order mark; anything else is likely Windows Latin.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        throw ImportError.unreadableFile
    }
}

extension FeedingSession {
    /// Every session brought in by an import, of any kind.
    static func imported() -> FetchDescriptor<FeedingSession> {
        let imported = EntrySource.imported.rawValue
        return FetchDescriptor<FeedingSession>(predicate: #Predicate { $0.sourceRaw == imported })
    }
}
