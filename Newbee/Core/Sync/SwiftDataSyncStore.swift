import Foundation
import NewbeeKit
import SwiftData

/// The SwiftData store as sync sees it: feeds and the baby profile as payloads
/// (docs/ICLOUD_SYNC.md). `SyncCore` decides what moves; this only reads and writes.
@MainActor
final class SwiftDataSyncStore: SyncLocalStore {
    /// A CloudKit record holds up to 1 MB. The photo is a small JPEG (`BabyPhotoStore`), far
    /// below this; anything bigger stays on the phone rather than stopping the record from syncing.
    nonisolated static let maxPhotoBytes = 700_000

    /// Held so the container outlives the context (see `SwiftDataFeedingRepository`).
    private let container: ModelContainer
    private let context: ModelContext

    private let origins: FeedOrigins
    /// Tonight's shift lives outside SwiftData but syncs with everything else.
    private let nightShift: NightShiftStore?

    init(container: ModelContainer, origins: FeedOrigins = FeedOrigins(), nightShift: NightShiftStore? = nil) {
        self.container = container
        self.context = container.mainContext
        self.origins = origins
        self.nightShift = nightShift
    }

    func items() throws -> [SyncKey: SyncLocalItem] {
        var items: [SyncKey: SyncLocalItem] = [:]
        var sessions = FetchDescriptor<FeedingSession>()
        // One query per relationship instead of one per feed.
        sessions.relationshipKeyPathsForPrefetching = [\.segments, \.bottle, \.pump]
        for session in try context.fetch(sessions) {
            let payload = session.syncPayload
            items[payload.key] = SyncLocalItem(fingerprint: payload.fingerprint(), changedAt: session.modifiedAt)
        }
        for baby in try context.fetch(FetchDescriptor<Baby>()) {
            let payload = baby.syncPayload
            items[payload.key] = SyncLocalItem(fingerprint: payload.fingerprint(attachment: baby.syncPhoto), changedAt: baby.createdAt)
        }
        if let shift = nightShift?.shift {
            items[shift.key] = SyncLocalItem(fingerprint: shift.fingerprint(), changedAt: shift.changedAt)
        }
        return items
    }

    func content(for key: SyncKey) throws -> SyncContent? {
        if key.kind == .nightShift {
            return key.id == NightShift.recordID ? nightShift?.shift?.content() : nil
        }
        guard let id = UUID(uuidString: key.id) else { return nil }
        switch key.kind {
        case .nightShift:
            return nil
        case .feed:
            return try session(id: id)?.syncPayload.content()
        case .baby:
            guard let baby = try baby(id: id) else { return nil }
            return baby.syncPayload.content(attachment: baby.syncPhoto)
        }
    }

    func apply(_ contents: [SyncKey: SyncContent]) throws -> [SyncKey: Int64] {
        do {
            // Babies first, so the feeds that follow have a profile to attach to.
            var babies: [Baby] = []
            for (key, content) in contents where key.kind == .baby {
                guard let payload = BabyPayload.decode(content), payload.key == key else { continue }
                let baby: Baby
                if let existing = try self.baby(id: payload.id) {
                    baby = existing
                } else {
                    baby = Baby(id: payload.id)
                    context.insert(baby)
                }
                baby.apply(payload, photo: content.attachment)
                babies.append(baby)
            }

            let payloads = contents.compactMap { key, content -> FeedPayload? in
                guard key.kind == .feed, let payload = FeedPayload.decode(content), payload.key == key else { return nil }
                return payload
            }
            var sessions: [FeedingSession] = []
            if !payloads.isEmpty {
                var existing = try existingSessions(ids: payloads.map(\.id))
                let primary = Baby.primary(in: context)
                for payload in payloads {
                    let session: FeedingSession
                    if let found = existing[payload.id] {
                        session = found
                    } else {
                        session = FeedingSession(id: payload.id, kind: .breast, status: .completed, startedAt: payload.startedAt)
                        context.insert(session)
                        existing[payload.id] = session
                        // A feed that is still running on the phone it was started on.
                        if payload.status != SessionStatus.completed.rawValue {
                            origins.markStartedElsewhere(payload.id)
                        }
                    }
                    session.apply(payload, in: context)
                    // One baby profile: every feed belongs to it. `BabyMerge` attaches any feed
                    // that arrives before the profile does.
                    if session.baby == nil {
                        session.baby = primary
                    }
                    sessions.append(session)
                }
            }
            try context.save()

            var stored: [SyncKey: Int64] = [:]
            for (key, content) in contents where key.kind == .nightShift {
                guard let nightShift, let shift = NightShift.decode(content), shift.key == key else { continue }
                nightShift.applyFromSync(shift)
                stored[key] = shift.fingerprint()
            }
            for baby in babies {
                let payload = baby.syncPayload
                stored[payload.key] = payload.fingerprint(attachment: baby.syncPhoto)
            }
            for session in sessions {
                let payload = session.syncPayload
                stored[payload.key] = payload.fingerprint()
            }
            return stored
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(_ keys: [SyncKey]) throws {
        do {
            for key in keys {
                if key.kind == .nightShift {
                    nightShift?.applyFromSync(nil)
                    continue
                }
                guard let id = UUID(uuidString: key.id) else { continue }
                switch key.kind {
                case .nightShift:
                    break
                case .feed:
                    try session(id: id)?.deleteWithChildren(from: context)
                case .baby:
                    // Its feeds stay (the relationship nullifies) and join the remaining profile.
                    if let baby = try baby(id: id) {
                        context.delete(baby)
                    }
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Helpers

    private func session(id: UUID) throws -> FeedingSession? {
        var descriptor = FetchDescriptor<FeedingSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func baby(id: UUID) throws -> Baby? {
        var descriptor = FetchDescriptor<Baby>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The stored sessions among `ids`. A first sync brings thousands at once, so a big batch
    /// reads every session in one query rather than passing a huge list to the store.
    private func existingSessions(ids: [UUID]) throws -> [UUID: FeedingSession] {
        let descriptor: FetchDescriptor<FeedingSession>
        if ids.count > 200 {
            descriptor = FetchDescriptor<FeedingSession>()
        } else {
            descriptor = FetchDescriptor<FeedingSession>(predicate: #Predicate { ids.contains($0.id) })
        }
        return Dictionary(try context.fetch(descriptor).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Mapping

extension Baby {
    var syncPayload: BabyPayload {
        BabyPayload(id: id, name: name, birthDate: birthDate, createdAt: createdAt)
    }

    /// The photo as it syncs: left out when it is too big for a record.
    var syncPhoto: Data? {
        guard let photoData, photoData.count <= SwiftDataSyncStore.maxPhotoBytes else { return nil }
        return photoData
    }

    func apply(_ payload: BabyPayload, photo: Data?) {
        name = payload.name
        birthDate = payload.birthDate
        createdAt = payload.createdAt
        // A photo too big to sync never left this phone, so a record without one doesn't remove it.
        if photo != nil || syncPhoto != nil {
            photoData = photo
        }
    }
}

extension FeedingSession {
    var syncPayload: FeedPayload {
        FeedPayload(
            id: id,
            kind: kindRaw,
            status: statusRaw,
            startedAt: startedAt,
            endedAt: endedAt,
            timeZoneID: timeZoneID,
            notes: notes,
            source: sourceRaw,
            needsReview: needsReview,
            recoveryAcknowledgedAt: recoveryAcknowledgedAt,
            revision: revision,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            segments: (segments ?? []).map {
                FeedPayload.Segment(
                    id: $0.id, side: $0.sideRaw, startedAt: $0.startedAt, endedAt: $0.endedAt,
                    startMonotonic: $0.startMonotonic, startBootID: $0.startBootID
                )
            },
            bottle: bottle.map {
                FeedPayload.Bottle(
                    contents: $0.contentsRaw, amountML: $0.amountML, enteredUnit: $0.enteredUnitRaw, durationSeconds: $0.durationSeconds
                )
            },
            pump: pump.map {
                FeedPayload.Pump(
                    leftML: $0.leftML, rightML: $0.rightML, enteredUnit: $0.enteredUnitRaw, durationSeconds: $0.durationSeconds,
                    totalOnly: $0.isTotalOnly
                )
            }
        )
    }

    /// Makes this session, its segments and its bottle or pump details match `payload`.
    func apply(_ payload: FeedPayload, in context: ModelContext) {
        kindRaw = payload.kind
        statusRaw = payload.status
        startedAt = payload.startedAt
        endedAt = payload.endedAt
        timeZoneID = payload.timeZoneID
        notes = payload.notes
        sourceRaw = payload.source
        needsReview = payload.needsReview
        recoveryAcknowledgedAt = payload.recoveryAcknowledgedAt
        revision = payload.revision
        createdAt = payload.createdAt
        modifiedAt = payload.modifiedAt

        var existing = Dictionary((segments ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var updated: [FeedingSegment] = []
        for segment in payload.segments {
            let model: FeedingSegment
            if let found = existing.removeValue(forKey: segment.id) {
                model = found
            } else {
                model = FeedingSegment(id: segment.id, side: .left, startedAt: segment.startedAt)
                context.insert(model)
            }
            model.sideRaw = segment.side
            model.startedAt = segment.startedAt
            model.endedAt = segment.endedAt
            model.startMonotonic = segment.startMonotonic
            model.startBootID = segment.startBootID
            updated.append(model)
        }
        for orphan in existing.values {
            context.delete(orphan)
        }
        segments = updated

        if let details = payload.bottle {
            let model: BottleDetails
            if let bottle {
                model = bottle
            } else {
                model = BottleDetails(contents: .other, amountML: details.amountML, enteredUnit: .milliliters)
                context.insert(model)
                bottle = model
            }
            model.contentsRaw = details.contents
            model.amountML = details.amountML
            model.enteredUnitRaw = details.enteredUnit
            model.durationSeconds = details.durationSeconds
        } else if let bottle {
            context.delete(bottle)
            self.bottle = nil
        }

        if let details = payload.pump {
            let model: PumpDetails
            if let pump {
                model = pump
            } else {
                model = PumpDetails(leftML: details.leftML, rightML: details.rightML, enteredUnit: .milliliters)
                context.insert(model)
                pump = model
            }
            model.leftML = details.leftML
            model.rightML = details.rightML
            model.enteredUnitRaw = details.enteredUnit
            model.durationSeconds = details.durationSeconds
            model.isTotalOnly = details.isTotalOnly
        } else if let pump {
            context.delete(pump)
            self.pump = nil
        }
    }
}
