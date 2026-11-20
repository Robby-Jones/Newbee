import CloudKit
import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// The SwiftData side of sync: feeds and the baby profile as payloads, and back
/// (docs/ICLOUD_SYNC.md). The rules for what syncs when are tested in NewbeeKit's `SyncTests`.
@MainActor
@Suite("Sync store")
struct SyncStoreTests {
    let now = Date(timeIntervalSince1970: 1_793_944_800)

    private func breastfeed(in context: ModelContext) -> FeedingSession {
        let session = FeedingSession(kind: .breast, status: .completed, startedAt: now.addingTimeInterval(-1_200), source: .timer)
        session.endedAt = now
        session.notes = "Sleepy"
        session.revision = 3
        session.modifiedAt = now
        context.insert(session)
        let left = FeedingSegment(side: .left, startedAt: now.addingTimeInterval(-1_200), endedAt: now.addingTimeInterval(-600), startMonotonic: 12.5, startBootID: "boot")
        let right = FeedingSegment(side: .right, startedAt: now.addingTimeInterval(-500), endedAt: now)
        context.insert(left)
        context.insert(right)
        session.segments = [right, left]
        return session
    }

    private func bottle(in context: ModelContext) -> FeedingSession {
        let session = FeedingSession(kind: .bottle, status: .completed, startedAt: now, source: .manual)
        session.endedAt = now
        context.insert(session)
        let details = BottleDetails(contents: .formula, amountML: 88.72, enteredUnit: .fluidOunces, durationSeconds: 300)
        context.insert(details)
        session.bottle = details
        return session
    }

    private func pump(in context: ModelContext) -> FeedingSession {
        let session = FeedingSession(kind: .pump, status: .completed, startedAt: now, source: .manual)
        context.insert(session)
        let details = PumpDetails(leftML: 60, rightML: 45.5, enteredUnit: .milliliters, durationSeconds: 900)
        context.insert(details)
        session.pump = details
        return session
    }

    /// Everything on one phone arrives on another exactly as it was.
    @Test func everyKindOfEntryCrossesToAnotherStore() throws {
        let here = try makeInMemoryContainer()
        let there = try makeInMemoryContainer()
        let context = here.mainContext
        let baby = Baby(name: "Ella", birthDate: now.addingTimeInterval(-86_400 * 12), createdAt: now.addingTimeInterval(-86_400))
        baby.photoData = Data([1, 2, 3, 4])
        context.insert(baby)
        let sessions = [breastfeed(in: context), bottle(in: context), pump(in: context)]
        for session in sessions {
            session.baby = baby
        }
        try context.save()

        let source = SwiftDataSyncStore(container: here)
        let target = SwiftDataSyncStore(container: there)
        let items = try source.items()
        #expect(items.count == 4)
        var contents: [SyncKey: SyncContent] = [:]
        for key in items.keys {
            // A guard rather than #require: Xcode 27's Swift Testing wrongly flags #require on this
            // optional as redundant.
            guard let content = try source.content(for: key) else {
                Issue.record("No content for \(key)")
                return
            }
            contents[key] = content
        }
        let stored = try target.apply(contents)

        // Same fingerprints on both sides, so nothing bounces back as a change.
        #expect(stored == items.mapValues(\.fingerprint))
        #expect(try target.items().mapValues(\.fingerprint) == items.mapValues(\.fingerprint))

        let copies = try there.mainContext.fetch(FetchDescriptor<FeedingSession>())
        #expect(copies.count == 3)
        let copiedBaby = try #require(try there.mainContext.fetch(FetchDescriptor<Baby>()).first)
        #expect(copiedBaby.id == baby.id)
        #expect(copiedBaby.name == "Ella")
        #expect(copiedBaby.photoData == Data([1, 2, 3, 4]))
        // Feeds are attached to the one baby profile.
        #expect(copies.allSatisfy { $0.baby?.id == baby.id })

        let breast = try #require(copies.first { $0.kind == .breast })
        #expect(breast.sessionSnapshot == sessions[0].sessionSnapshot)
        #expect(breast.orderedSegments.map(\.side) == [.left, .right])
        #expect(breast.orderedSegments.first?.startBootID == "boot")
        let copiedBottle = try #require(copies.first { $0.kind == .bottle })
        #expect(copiedBottle.bottle?.amountML == 88.72)
        #expect(copiedBottle.bottle?.contents == .formula)
        #expect(copiedBottle.bottle?.enteredUnit == .fluidOunces)
        #expect(copiedBottle.bottle?.durationSeconds == 300)
        let copiedPump = try #require(copies.first { $0.kind == .pump })
        #expect(copiedPump.pump?.leftML == 60)
        #expect(copiedPump.pump?.rightML == 45.5)
    }

    /// A pumping session logged as a total stays a total on the other phone, and editing it there
    /// into one with sides clears the mark.
    @Test func aTotalOnlyPumpCrossesWithItsMark() throws {
        let here = try makeInMemoryContainer()
        let there = try makeInMemoryContainer()
        let context = here.mainContext
        let session = pump(in: context)
        session.pump?.isTotalOnly = true
        try context.save()

        let source = SwiftDataSyncStore(container: here)
        let target = SwiftDataSyncStore(container: there)
        var contents: [SyncKey: SyncContent] = [:]
        for key in try source.items().keys {
            guard let content = try source.content(for: key) else {
                Issue.record("No content for \(key)")
                return
            }
            contents[key] = content
        }
        _ = try target.apply(contents)
        let copy = try #require(try there.mainContext.fetch(FetchDescriptor<FeedingSession>()).first)
        #expect(copy.pump?.isTotalOnly == true)
        #expect(copy.pumpEntry?.isTotalOnly == true)

        session.pump?.isTotalOnly = false
        try context.save()
        for key in contents.keys {
            guard let content = try source.content(for: key) else { continue }
            contents[key] = content
        }
        _ = try target.apply(contents)
        #expect(copy.pump?.isTotalOnly == false)
    }

    /// A later version of a feed replaces the stored one, segments included, without duplicates.
    @Test func applyingAnEditUpdatesInPlace() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let session = breastfeed(in: context)
        try context.save()
        let store = SwiftDataSyncStore(container: container)

        var payload = session.syncPayload
        payload.notes = "Edited on the other phone"
        payload.segments.removeLast()
        payload.segments[0].endedAt = now
        let stored = try store.apply([payload.key: payload.content()])

        #expect(stored[payload.key] == payload.fingerprint())
        #expect(try context.fetchCount(FetchDescriptor<FeedingSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<FeedingSegment>()) == 1)
        #expect(session.notes == "Edited on the other phone")
        #expect(session.orderedSegments.first?.endedAt == now)
    }

    /// "Still feeding?" belongs to the phone that started the timer: a running feed that arrives
    /// through sync is remembered as started elsewhere; one that arrives finished is not.
    @Test func runningFeedsFromAnotherPhoneAreRemembered() throws {
        let here = try makeInMemoryContainer()
        let there = try makeInMemoryContainer()
        let finished = breastfeed(in: here.mainContext)
        let running = FeedingSession(kind: .breast, status: .active, startedAt: now, source: .timer)
        here.mainContext.insert(running)
        let segment = FeedingSegment(side: .left, startedAt: now)
        here.mainContext.insert(segment)
        running.segments = [segment]
        try here.mainContext.save()

        let suite = "FeedOriginsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let origins = FeedOrigins(defaults: defaults)
        let store = SwiftDataSyncStore(container: there, origins: origins)
        let payloads = [finished.syncPayload, running.syncPayload]
        _ = try store.apply(Dictionary(uniqueKeysWithValues: payloads.map { ($0.key, $0.content()) }))

        #expect(origins.wasStartedHere(running.id) == false)
        #expect(origins.wasStartedHere(finished.id))
        // A feed this phone started itself was never applied from sync.
        #expect(origins.wasStartedHere(UUID()))
    }

    /// A bottle changed into nothing but a note still drops its details row.
    @Test func detailsThatAreGoneAreRemoved() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let session = bottle(in: context)
        try context.save()
        let store = SwiftDataSyncStore(container: container)

        var payload = session.syncPayload
        payload.bottle = nil
        _ = try store.apply([payload.key: payload.content()])
        #expect(session.bottle == nil)
        #expect(try context.fetchCount(FetchDescriptor<BottleDetails>()) == 0)
    }

    @Test func deletingRemovesTheFeedAndItsParts() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let session = breastfeed(in: context)
        let other = bottle(in: context)
        try context.save()
        let store = SwiftDataSyncStore(container: container)

        try store.delete([session.syncPayload.key, SyncKey(kind: .feed, id: UUID())])
        #expect(try context.fetch(FetchDescriptor<FeedingSession>()).map(\.id) == [other.id])
        #expect(try context.fetchCount(FetchDescriptor<FeedingSegment>()) == 0)
    }

    /// Feeds that arrive before any baby profile exists are picked up by the profile later.
    @Test func feedsWithoutAProfileJoinItLater() throws {
        let source = try makeInMemoryContainer()
        let session = bottle(in: source.mainContext)
        try source.mainContext.save()
        let payload = session.syncPayload

        let container = try makeInMemoryContainer()
        let store = SwiftDataSyncStore(container: container)
        _ = try store.apply([payload.key: payload.content()])
        let baby = BabyPayload(id: UUID(), name: "Ella", birthDate: nil, createdAt: now)
        _ = try store.apply([baby.key: baby.content()])
        try BabyMerge.mergeDuplicates(in: container.mainContext)
        let copy = try #require(try container.mainContext.fetch(FetchDescriptor<FeedingSession>()).first)
        #expect(copy.baby?.id == baby.id)
    }

    /// Records this build can't read are skipped, and the rest of the batch still lands.
    @Test func unreadableRecordsAreSkipped() throws {
        let source = try makeInMemoryContainer()
        let session = bottle(in: source.mainContext)
        try source.mainContext.save()
        let payload = session.syncPayload

        let container = try makeInMemoryContainer()
        let store = SwiftDataSyncStore(container: container)
        let broken = SyncKey(kind: .feed, id: UUID())
        let stored = try store.apply([
            payload.key: payload.content(),
            broken: SyncContent(body: Data("{}".utf8)),
        ])
        #expect(Array(stored.keys) == [payload.key])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSession>()) == 1)
    }

    /// Two phones, each with its own store, kept in step by `SyncCore` alone.
    @Test func twoStoresStayInStepThroughTheSyncCore() throws {
        let clock = TestClock(wall: now)
        let here = try makeInMemoryContainer()
        let there = try makeInMemoryContainer()
        let mine = SyncCore(store: SwiftDataSyncStore(container: here), clock: clock)
        let theirs = SyncCore(store: SwiftDataSyncStore(container: there), clock: clock)

        func send(from sender: SyncCore, to receiver: SyncCore) throws {
            let pending = try sender.scan()
            var records: [SyncRecord] = []
            for key in pending.saves {
                var record = try #require(try sender.outgoingRecord(for: key))
                record.systemFields = Data("tag".utf8)
                sender.didSave(record)
                records.append(record)
            }
            for key in pending.deletes {
                sender.didDelete(key)
            }
            try receiver.receive(modifications: records, deletions: Array(pending.deletes))
        }

        let session = breastfeed(in: here.mainContext)
        try here.mainContext.save()
        try send(from: mine, to: theirs)
        let copy = try #require(try there.mainContext.fetch(FetchDescriptor<FeedingSession>()).first)
        #expect(copy.sessionSnapshot == session.sessionSnapshot)
        // The copy isn't sent back as if it were a change.
        #expect(try theirs.scan().isEmpty)
        #expect(try mine.scan().isEmpty)

        clock.advance(by: 60)
        copy.notes = "Changed on the other phone"
        try there.mainContext.save()
        try send(from: theirs, to: mine)
        #expect(session.notes == "Changed on the other phone")

        clock.advance(by: 60)
        session.deleteWithChildren(from: here.mainContext)
        try here.mainContext.save()
        try send(from: mine, to: theirs)
        #expect(try there.mainContext.fetchCount(FetchDescriptor<FeedingSession>()) == 0)
        #expect(try there.mainContext.fetchCount(FetchDescriptor<FeedingSegment>()) == 0)
    }

    /// Sync finds out about changes from these notifications, so they must fire on every save.
    @Test func savingTheStoreAnnouncesIt() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let announced = Announced()
        var observers: [NSObjectProtocol] = []
        for name in [ModelContext.didSave, .NSManagedObjectContextDidSave] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                announced.note()
            })
        }
        defer {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        _ = bottle(in: context)
        try context.save()
        #expect(announced.count > 0)
    }

    // MARK: - CloudKit records

    @Test func aRecordSurvivesTheTripThroughCloudKit() throws {
        let baby = BabyPayload(id: UUID(), name: "Ella", birthDate: nil, createdAt: now)
        let record = SyncRecord(key: baby.key, changedAt: now, content: baby.content(attachment: Data([7, 7])))
        let zoneID = CKRecordZone.ID(zoneName: CloudSyncEngine.zoneName, ownerName: CKCurrentUserDefaultName)
        let cloud = CloudRecordCoding.cloudRecord(for: record, in: zoneID)
        #expect(cloud.recordType == "Baby")
        #expect(cloud.recordID.recordName == baby.id.uuidString)
        #expect(cloud.recordID.zoneID == zoneID)

        let back = try #require(CloudRecordCoding.syncRecord(from: cloud))
        #expect(back.key == record.key)
        #expect(back.changedAt == now)
        #expect(back.content == record.content)

        // A second save starts from the server's copy, so it carries its change tag.
        let systemFields = try #require(back.systemFields)
        var edited = back
        edited.content = baby.content()
        let second = CloudRecordCoding.cloudRecord(for: edited, in: zoneID)
        #expect(second.recordID == cloud.recordID)
        #expect(second[CloudRecordCoding.Field.photo] == nil)
        #expect(CloudRecordCoding.decodeSystemFields(systemFields)?.recordID == cloud.recordID)

        // The server's copy from another zone is never reused.
        let otherZone = CKRecordZone.ID(zoneName: CloudSyncEngine.zoneName, ownerName: "_someoneElse")
        #expect(CloudRecordCoding.cloudRecord(for: edited, in: otherZone).recordID.zoneID == otherZone)
    }

    @Test func recordsThatAreNotNewbeesAreIgnored() {
        let zoneID = CKRecordZone.ID(zoneName: CloudSyncEngine.zoneName, ownerName: CKCurrentUserDefaultName)
        #expect(CloudRecordCoding.syncRecord(from: CKRecord(recordType: "Something", recordID: CKRecord.ID(recordName: "x", zoneID: zoneID))) == nil)
        #expect(CloudRecordCoding.syncRecord(from: CKRecord(recordType: "Feed", recordID: CKRecord.ID(recordName: "x", zoneID: zoneID))) == nil)
    }

    // MARK: - Saved state

    @Test func syncStateSurvivesARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "CloudSync-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CloudSyncStateFile(url: url)
        #expect(file.load().ledger.entries.isEmpty)

        var state = CloudSyncState()
        let key = SyncKey(kind: .feed, id: UUID())
        var ledger = SyncLedger()
        ledger.scan(local: [key: SyncLocalItem(fingerprint: -42, changedAt: now)], now: now)
        ledger.saved(key, fingerprint: -42, systemFields: Data([1, 2, 3]))
        state.ledger = ledger
        state.joinedZone = CloudSyncState.Zone(CKRecordZone.ID(zoneName: "Family", ownerName: "_partner"))
        state.ownZoneExists = true
        try file.save(state)

        let loaded = file.load()
        #expect(loaded.ledger == ledger)
        #expect(loaded.joinedZone?.id == CKRecordZone.ID(zoneName: "Family", ownerName: "_partner"))
        #expect(loaded.ownZoneExists)
    }

    // MARK: - Fingerprints

    /// The same values NewbeeKit's tests pin on Linux: every platform must compute the same
    /// fingerprint, and it must never change.
    @Test func fingerprintsMatchEveryOtherPlatform() {
        let feed = FeedPayload(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, kind: "breast", status: "completed",
            startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), endedAt: Date(timeIntervalSinceReferenceDate: 800_000_900.5),
            timeZoneID: "America/Chicago", notes: "Sleepy 😴", source: "timer", needsReview: false,
            recoveryAcknowledgedAt: nil, revision: 4,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), modifiedAt: Date(timeIntervalSinceReferenceDate: 800_000_901),
            segments: [
                .init(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!, side: "left",
                      startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), endedAt: Date(timeIntervalSinceReferenceDate: 800_000_900.5),
                      startMonotonic: 1234.5, startBootID: "boot"),
            ],
            bottle: nil, pump: nil
        )
        #expect(feed.fingerprint() == 7_465_518_140_352_207_749)
        let baby = BabyPayload(
            id: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!, name: "Ella", birthDate: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 790_000_000)
        )
        #expect(baby.fingerprint(attachment: Data([1, 2, 3])) == -703_567_800_009_309_635)
    }

    // MARK: - Sharing

    @Test func sharingStatusFollowsWhoIsOnTheLog() {
        typealias Participant = CloudSharing.Participant
        let owner = Participant(isOwner: true, hasAccepted: true)
        #expect(CloudSharing.status(for: [], joined: false) == .notShared)
        #expect(CloudSharing.status(for: [owner], joined: false) == .notShared)
        #expect(CloudSharing.status(for: [owner, Participant(isOwner: false, hasAccepted: false)], joined: false) == .invited)
        #expect(CloudSharing.status(for: [owner, Participant(isOwner: false, hasAccepted: true)], joined: false) == .shared)
        #expect(CloudSharing.status(for: [owner, Participant(isOwner: false, hasAccepted: true)], joined: true) == .joined)
    }

    @Test func deleteAllDataSaysWhoItReaches() {
        let own = DeleteAllDataSheet.warning(for: .notShared)
        #expect(DeleteAllDataSheet.warning(for: .invited) == own)
        #expect(own.contains("partner") == false)
        #expect(DeleteAllDataSheet.warning(for: .shared).contains("on your partner's iPhone"))
        #expect(DeleteAllDataSheet.warning(for: .joined).contains("Your partner keeps their feeds"))
        // With iCloud sync off, only this iPhone is cleared.
        #expect(DeleteAllDataSheet.warning(for: .notShared, syncs: false).contains("from this iPhone"))
        #expect(DeleteAllDataSheet.warning(for: .notShared, syncs: false).contains("other devices") == false)
    }

    @Test func sharingIsOfferedOnlyWithICloud() {
        #expect(SharingSection.canShare(.upToDate(nil)))
        #expect(SharingSection.canShare(.syncing))
        #expect(SharingSection.canShare(.signedOut) == false)
        #expect(SharingSection.canShare(.unavailable) == false)
        // With sync off, the row offers to turn it on, if there is an iCloud account.
        #expect(SharingSection.canShare(.off, hasAccount: true))
        #expect(SharingSection.canShare(.off, hasAccount: false) == false)
    }
}

/// Counts notifications delivered on whichever thread posts them.
private final class Announced: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }
    func note() { lock.withLock { value += 1 } }
}
