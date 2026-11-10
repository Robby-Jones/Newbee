import Foundation
import SwiftData

extension Baby {
    /// The baby the app shows: the oldest profile. Every device picks the same one, because the
    /// order only depends on synced values (`createdAt`, then `id`).
    static func primary(in context: ModelContext, creatingIfMissing: Bool = false) -> Baby? {
        if let baby = ((try? context.fetch(FetchDescriptor<Baby>())) ?? []).min(by: isOrderedBefore) {
            return baby
        }
        guard creatingIfMissing else { return nil }
        let baby = Baby()
        context.insert(baby)
        return baby
    }

    /// Oldest first; the ID breaks ties so every device agrees.
    static func isOrderedBefore(_ lhs: Baby, _ rhs: Baby) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Newbee shows one baby. Two devices that each made a profile before they first synced end up
/// with two `Baby` rows once iCloud brings them together, so the newer ones are merged into the
/// oldest (docs/ICLOUD_SYNC.md).
///
/// Every device may run the merge at the same time: they all keep the same baby and move the same
/// feeds, so the results agree. `Baby.sessions` nullifies on delete, so a feed that hasn't been
/// moved yet on some device is never deleted with its old baby; the next merge picks it up.
enum BabyMerge {
    /// Merges duplicate profiles into the primary one. Returns true if anything changed.
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) throws -> Bool {
        let babies = try context.fetch(FetchDescriptor<Baby>()).sorted(by: Baby.isOrderedBefore)
        let orphans = try context.fetch(FetchDescriptor<FeedingSession>(predicate: #Predicate { $0.baby == nil }))
        guard let kept = babies.first, babies.count > 1 || !orphans.isEmpty else { return false }

        do {
            for duplicate in babies.dropFirst() {
                // Fill in what the kept profile is missing; the kept profile wins otherwise.
                if kept.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !duplicate.name.isEmpty {
                    kept.name = duplicate.name
                }
                if kept.birthDate == nil {
                    kept.birthDate = duplicate.birthDate
                }
                if kept.photoData == nil {
                    kept.photoData = duplicate.photoData
                }
                for session in duplicate.sessions ?? [] {
                    session.baby = kept
                }
                duplicate.sessions = []
            }
            // Feeds left without a baby, e.g. by a delete on another device before this merge ran.
            for session in orphans {
                session.baby = kept
            }
            // Move the feeds first, in their own save, so they're never attached to a deleted baby.
            try context.save()
            for duplicate in babies.dropFirst() {
                context.delete(duplicate)
            }
            try context.save()
            return true
        } catch {
            context.rollback()
            throw error
        }
    }
}
