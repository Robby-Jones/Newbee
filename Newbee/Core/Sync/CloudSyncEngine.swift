import CloudKit
import CoreData
import Foundation
import NewbeeKit
import SwiftData
import UIKit
import os

/// Moves feeds and the baby profile between this phone and iCloud (docs/ICLOUD_SYNC.md).
///
/// SwiftData keeps everything on the phone, as before. This sends changes to one CloudKit zone and
/// takes in the changes other phones made:
/// - **On its own**, a parent's phone syncs with the "Family" zone in their private database, so
///   their other devices see the same log.
/// - **After joining** the other parent's shared log, it syncs with that parent's "Family" zone
///   instead, through the shared database. Both parents then read and write one log.
///
/// `CKSyncEngine` does the transport (pushes, batching, retries after network errors).
/// `SyncCore` decides what to send and what to do with what arrives; it has no CloudKit in it and
/// is tested on its own.
@MainActor
final class CloudSyncEngine {
    static let zoneName = "Family"
    /// How many records go into one send. More are sent in further batches.
    private static let batchSize = 150

    let container: CKContainer
    /// This parent's own zone.
    let ownZoneID = CKRecordZone.ID(zoneName: CloudSyncEngine.zoneName, ownerName: CKCurrentUserDefaultName)

    /// Runs after this phone joins or leaves a shared log, or the share itself changed.
    var onSharingChange: (@MainActor () -> Void)?

    private let core: SyncCore
    private let monitor: CloudSyncMonitor
    private let file: CloudSyncStateFile
    private let clock: any AppClock
    private let log = Logger(subsystem: "com.robbyjones.newbee", category: "sync")

    private var state: CloudSyncState
    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?
    private var observers: [NSObjectProtocol] = []
    private var scanTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    /// Records the server refused, and when to try each again.
    private var blocked: [SyncKey: (until: Date, delay: TimeInterval)] = [:]
    /// The running fetch or send of each engine, for the Settings status.
    private var activity: [String: UUID] = [:]
    /// An engine is rebuilt at most once per launch after a failed write to the store.
    private var didResetEngine = false

    init(containerID: String, modelContainer: ModelContainer, monitor: CloudSyncMonitor, file: CloudSyncStateFile, clock: any AppClock) {
        container = CKContainer(identifier: containerID)
        self.monitor = monitor
        self.file = file
        self.clock = clock
        let state = file.load()
        self.state = state
        core = SyncCore(store: SwiftDataSyncStore(container: modelContainer), ledger: state.ledger, clock: clock)
    }

    // MARK: - Lifecycle

    /// Starts syncing. Call once, as early as possible: iOS launches the app in the background to
    /// deliver changes from other phones.
    func start() {
        guard privateEngine == nil else { return }
        privateEngine = makeEngine(database: container.privateCloudDatabase, serialization: state.privateEngine)
        sharedEngine = makeEngine(database: container.sharedCloudDatabase, serialization: state.sharedEngine)

        // Every save to the store, from any screen, Lock Screen button or import.
        let center = NotificationCenter.default
        for name in [ModelContext.didSave, .NSManagedObjectContextDidSave] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // The engine lives as long as the app (`AppDependencies.shared`).
                Task { @MainActor in self.localDataDidChange() }
            })
        }
        enqueuePending()
    }

    private func makeEngine(database: CKDatabase, serialization: CKSyncEngine.State.Serialization?) -> CKSyncEngine {
        CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: serialization, delegate: self))
    }

    /// Something in the store changed. Changes that come in quick succession are sent together.
    func localDataDidChange() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.enqueuePending()
            // A Lock Screen button changed a feed while the app is in the background: send now,
            // before iOS suspends the app again.
            if UIApplication.shared.applicationState != .active {
                await self.sendNow()
            }
        }
    }

    /// The app came to the front: try again whatever the server refused, and look for changes.
    func appBecameActive() {
        blocked = [:]
        enqueuePending()
        Task { [weak self] in
            try? await self?.privateEngine?.fetchChanges()
            try? await self?.sharedEngine?.fetchChanges()
        }
    }

    /// Sends everything that is waiting, asking iOS for a little time if the app is leaving the
    /// foreground.
    func sendNow() async {
        scanTask?.cancel()
        enqueuePending()
        guard let engine = activeEngine else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "Newbee sync")
        try? await engine.sendChanges()
        persistNow()
        UIApplication.shared.endBackgroundTask(task)
    }

    // MARK: - Which log

    /// True once this parent has joined the other parent's shared log.
    var isJoined: Bool { state.joinedZone != nil }

    /// The zone this phone syncs with now.
    var activeZoneID: CKRecordZone.ID { state.joinedZone?.id ?? ownZoneID }

    /// The database that zone is in.
    var activeDatabase: CKDatabase {
        isJoined ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private var activeEngine: CKSyncEngine? {
        isJoined ? sharedEngine : privateEngine
    }

    /// Creates this parent's zone if it isn't there yet. Sharing needs it to exist.
    func ensureOwnZone() async throws {
        guard !state.ownZoneExists else { return }
        _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: ownZoneID))
        state.ownZoneExists = true
        persistSoon()
    }

    /// Brings in everything from this parent's own iCloud.
    func fetchOwnChanges() async throws {
        try await privateEngine?.fetchChanges()
    }

    /// Looks for a shared log this parent was invited to, and for changes in it.
    func fetchSharedChanges() async throws {
        try await sharedEngine?.fetchChanges()
    }

    /// This parent accepted an invitation: from now on the phone syncs with the other parent's
    /// log. Their own feeds are merged into it; where both have the same feed, the one changed
    /// last wins.
    private func join(_ zoneID: CKRecordZone.ID) {
        log.info("Joining shared log \(zoneID.zoneName, privacy: .public)")
        state.joinedZone = CloudSyncState.Zone(zoneID)
        startOver()
        clearPending(privateEngine)
        onSharingChange?()
    }

    /// The shared log is gone (the other parent stopped sharing, or this one left). Every feed
    /// stays on this phone and syncs with this parent's own iCloud again.
    private func leaveJoinedZone() {
        guard isJoined else { return }
        log.info("Leaving shared log")
        state.joinedZone = nil
        state.ownZoneExists = false
        startOver()
        clearPending(sharedEngine)
        onSharingChange?()
    }

    /// Syncing starts over against another zone or account. Nothing on the phone changes.
    private func startOver() {
        core.forgetServer()
        blocked = [:]
        monitor.setSendError(nil)
    }

    private func clearPending(_ engine: CKSyncEngine?) {
        guard let engine else { return }
        let pending = engine.state.pendingRecordZoneChanges
        if !pending.isEmpty {
            engine.state.remove(pendingRecordZoneChanges: pending)
        }
    }

    /// Once everything of this parent's is in the shared log, their own zone is only a stale copy.
    /// Removing it means a later reinstall can't bring back feeds that were deleted since.
    private func deleteOwnZoneIfJoined() {
        guard isJoined, state.ownZoneExists, core.ledger.pending.isEmpty, let privateEngine else { return }
        privateEngine.state.add(pendingDatabaseChanges: [.deleteZone(ownZoneID)])
    }

    // MARK: - Sending

    /// Compares the store with what iCloud has and queues everything that differs.
    func enqueuePending() {
        guard let engine = activeEngine else { return }
        let zoneID = activeZoneID
        do {
            let pending = try core.scan()
            let now = clock.now
            blocked = blocked.filter { pending.saves.contains($0.key) || pending.deletes.contains($0.key) }
            var changes: [CKSyncEngine.PendingRecordZoneChange] = []
            for key in pending.saves where !isBlocked(key, at: now) {
                changes.append(.saveRecord(CloudRecordCoding.recordID(for: key, in: zoneID)))
            }
            for key in pending.deletes where !isBlocked(key, at: now) {
                changes.append(.deleteRecord(CloudRecordCoding.recordID(for: key, in: zoneID)))
            }
            if !isJoined, !state.ownZoneExists {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            }
            if !changes.isEmpty {
                engine.state.add(pendingRecordZoneChanges: changes)
            }
            if blocked.isEmpty {
                monitor.setSendError(nil)
            }
            deleteOwnZoneIfJoined()
        } catch {
            log.error("Couldn't read the store for sync: \(error.localizedDescription, privacy: .public)")
        }
        persistSoon()
    }

    private func isBlocked(_ key: SyncKey, at now: Date) -> Bool {
        guard let block = blocked[key] else { return false }
        return block.until > now
    }

    /// The server refused `key` for a reason that waiting might fix (the schema isn't deployed yet,
    /// iCloud storage is full). Try again later, a little less often each time.
    private func block(_ key: SyncKey, error: CKError) {
        let delay = min((blocked[key]?.delay ?? 15) * 2, 3_600)
        blocked[key] = (clock.now.addingTimeInterval(delay), delay)
        monitor.setSendError(CloudSyncEvent.message(for: error))
        log.error("Couldn't send \(key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
        retryTask?.cancel()
        let wait = blocked.values.map(\.delay).min() ?? delay
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.enqueuePending()
        }
    }

    /// The item a record belongs to. Record names are the item IDs, which are unique across kinds.
    private func key(for recordID: CKRecord.ID) -> SyncKey? {
        SyncRecordKind.allCases
            .map { SyncKey(kind: $0, id: recordID.recordName) }
            .first { core.ledger[$0] != nil }
    }

    /// The next changes to send and the records for the saves among them, as the store is now.
    private func nextBatch(
        for engine: CKSyncEngine, context: CKSyncEngine.SendChangesContext
    ) -> (changes: [CKSyncEngine.PendingRecordZoneChange], records: [CKRecord.ID: CKRecord]) {
        let zoneID = activeZoneID
        let scope = context.options.scope
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        var records: [CKRecord.ID: CKRecord] = [:]
        var stale: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in engine.state.pendingRecordZoneChanges where scope.contains(change) {
            guard changes.count < Self.batchSize else { break }
            switch change {
            case .saveRecord(let recordID):
                if recordID.zoneID == zoneID, let key = key(for: recordID),
                   let record = try? core.outgoingRecord(for: key) {
                    records[recordID] = CloudRecordCoding.cloudRecord(for: record, in: zoneID)
                    changes.append(change)
                } else {
                    stale.append(change)
                }
            case .deleteRecord(let recordID):
                if recordID.zoneID == zoneID, let key = key(for: recordID), core.needsDelete(key) {
                    changes.append(change)
                } else {
                    stale.append(change)
                }
            @unknown default:
                stale.append(change)
            }
        }
        // Changes that no longer apply: the item was edited back, deleted, or belongs to a zone
        // this phone has stopped syncing with.
        if !stale.isEmpty {
            engine.state.remove(pendingRecordZoneChanges: stale)
        }
        return (changes, records)
    }

    private func handleSent(_ event: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        guard engine === activeEngine else { return }
        for cloud in event.savedRecords {
            if let record = CloudRecordCoding.syncRecord(from: cloud) {
                core.didSave(record)
                blocked[record.key] = nil
            }
        }
        for recordID in event.deletedRecordIDs {
            if let key = key(for: recordID) {
                core.didDelete(key)
                blocked[key] = nil
            }
        }

        var conflicts: [SyncRecord] = []
        var zoneLost = false
        for failure in event.failedRecordSaves {
            guard let key = key(for: failure.record.recordID) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                // Another phone saved this record first. `SyncCore` picks the later change.
                if let server = failure.error.serverRecord, let record = CloudRecordCoding.syncRecord(from: server) {
                    conflicts.append(record)
                } else {
                    core.serverLost(key)
                }
            case .unknownItem:
                // Deleted on the server since this phone last saw it. The edit here is kept.
                core.serverLost(key)
            case .zoneNotFound, .userDeletedZone:
                zoneLost = true
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
                 .notAuthenticated, .operationCancelled, .accountTemporarilyUnavailable:
                // `CKSyncEngine` sends these again on its own.
                break
            default:
                block(key, error: failure.error)
            }
        }
        for (recordID, error) in event.failedRecordDeletes {
            guard let key = key(for: recordID) else { continue }
            switch error.code {
            case .unknownItem:
                core.didDelete(key)
            case .zoneNotFound, .userDeletedZone:
                zoneLost = true
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
                 .notAuthenticated, .operationCancelled, .accountTemporarilyUnavailable:
                break
            default:
                block(key, error: error)
            }
        }

        if zoneLost {
            activeZoneWasLost()
        }
        if !conflicts.isEmpty {
            receive(modifications: conflicts, deletions: [], from: engine)
        }
        enqueuePending()
    }

    /// The zone this phone was sending to isn't there any more.
    private func activeZoneWasLost() {
        if isJoined {
            leaveJoinedZone()
        } else {
            // Deleted from another device or from iCloud settings. The phone still has every feed
            // and uploads them again.
            state.ownZoneExists = false
            startOver()
        }
    }

    // MARK: - Receiving

    private func handleFetched(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges, engine: CKSyncEngine) {
        guard engine === activeEngine else { return }
        let zoneID = activeZoneID
        var modifications: [SyncRecord] = []
        var deletions: [SyncKey] = []
        var shareChanged = false
        for modification in event.modifications where modification.record.recordID.zoneID == zoneID {
            if modification.record is CKShare {
                shareChanged = true
            } else if let record = CloudRecordCoding.syncRecord(from: modification.record) {
                modifications.append(record)
            }
        }
        for deletion in event.deletions where deletion.recordID.zoneID == zoneID {
            if deletion.recordType == CKRecord.SystemType.share {
                shareChanged = true
            } else if let kind = SyncRecordKind(rawValue: deletion.recordType) {
                deletions.append(SyncKey(kind: kind, id: deletion.recordID.recordName))
            }
        }
        receive(modifications: modifications, deletions: deletions, from: engine)
        if shareChanged {
            onSharingChange?()
        }
        enqueuePending()
    }

    private func receive(modifications: [SyncRecord], deletions: [SyncKey], from engine: CKSyncEngine) {
        do {
            if try core.receive(modifications: modifications, deletions: deletions) {
                monitor.didImportChanges()
            }
        } catch {
            // Nothing was written, but CloudKit considers these changes delivered. Fetch the whole
            // zone again rather than miss them.
            log.error("Couldn't write changes from iCloud: \(error.localizedDescription, privacy: .public)")
            refetchEverything(engine)
        }
    }

    private func refetchEverything(_ engine: CKSyncEngine) {
        guard !didResetEngine else { return }
        didResetEngine = true
        if engine === privateEngine {
            state.privateEngine = nil
            privateEngine = makeEngine(database: container.privateCloudDatabase, serialization: nil)
        } else if engine === sharedEngine {
            state.sharedEngine = nil
            sharedEngine = makeEngine(database: container.sharedCloudDatabase, serialization: nil)
        }
    }

    private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges, engine: CKSyncEngine) {
        if engine === privateEngine {
            if event.modifications.contains(where: { $0.zoneID == ownZoneID }) {
                state.ownZoneExists = true
            }
            if event.deletions.contains(where: { $0.zoneID == ownZoneID }) {
                state.ownZoneExists = false
                if !isJoined {
                    startOver()
                }
            }
        } else if engine === sharedEngine {
            if let joined = state.joinedZone?.id, event.deletions.contains(where: { $0.zoneID == joined }) {
                leaveJoinedZone()
            }
            if !isJoined, let zoneID = event.modifications.map(\.zoneID).first(where: { $0.zoneName == Self.zoneName }) {
                join(zoneID)
            }
        }
        enqueuePending()
    }

    private func handleSentDatabaseChanges(_ event: CKSyncEngine.Event.SentDatabaseChanges, engine: CKSyncEngine) {
        guard engine === privateEngine else { return }
        if event.savedZones.contains(where: { $0.zoneID == ownZoneID }) {
            state.ownZoneExists = true
        }
        if event.deletedZoneIDs.contains(ownZoneID) {
            state.ownZoneExists = false
        }
        for failure in event.failedZoneSaves {
            log.error("Couldn't create the zone: \(failure.error.localizedDescription, privacy: .public)")
            monitor.setSendError(CloudSyncEvent.message(for: failure.error))
        }
        persistSoon()
    }

    /// The iCloud account changed. Feeds always stay on the phone; they sync with whichever
    /// account is signed in.
    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange, engine: CKSyncEngine) {
        // Both engines report it; act once.
        guard engine === privateEngine else { return }
        state.joinedZone = nil
        state.ownZoneExists = false
        startOver()
        clearPending(sharedEngine)
        onSharingChange?()
        enqueuePending()
        Task { await monitor.refreshAccountStatus() }
    }

    // MARK: - Status

    private func began(_ kind: CloudSyncEvent.Kind, engine: CKSyncEngine) {
        let id = UUID()
        activity[activityKey(kind, engine)] = id
        monitor.handle(CloudSyncEvent(id: id, kind: kind, finished: false, succeeded: false, endDate: nil))
    }

    private func ended(_ kind: CloudSyncEvent.Kind, engine: CKSyncEngine) {
        guard let id = activity.removeValue(forKey: activityKey(kind, engine)) else { return }
        monitor.handle(CloudSyncEvent(id: id, kind: kind, finished: true, succeeded: true, endDate: clock.now))
    }

    private func activityKey(_ kind: CloudSyncEvent.Kind, _ engine: CKSyncEngine) -> String {
        "\(engine === privateEngine ? "private" : "shared")-\(kind)"
    }

    // MARK: - Saving state

    private func persistSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    func persistNow() {
        saveTask?.cancel()
        state.ledger = core.ledger
        do {
            try file.save(state)
        } catch {
            log.error("Couldn't save sync state: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncEngine: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // An engine that was replaced may still deliver an event or two.
        guard syncEngine === privateEngine || syncEngine === sharedEngine else { return }
        switch event {
        case .stateUpdate(let update):
            if syncEngine === privateEngine {
                state.privateEngine = update.stateSerialization
            } else {
                state.sharedEngine = update.stateSerialization
            }
            persistSoon()
        case .accountChange(let change):
            handleAccountChange(change, engine: syncEngine)
        case .fetchedDatabaseChanges(let changes):
            handleFetchedDatabaseChanges(changes, engine: syncEngine)
        case .fetchedRecordZoneChanges(let changes):
            handleFetched(changes, engine: syncEngine)
        case .sentDatabaseChanges(let sent):
            handleSentDatabaseChanges(sent, engine: syncEngine)
        case .sentRecordZoneChanges(let sent):
            handleSent(sent, engine: syncEngine)
        case .willFetchChanges:
            began(.import, engine: syncEngine)
        case .didFetchChanges:
            ended(.import, engine: syncEngine)
        case .willSendChanges:
            began(.export, engine: syncEngine)
        case .didSendChanges:
            ended(.export, engine: syncEngine)
        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === activeEngine else {
            // Nothing is sent to a zone this phone has stopped syncing with.
            clearPending(syncEngine)
            return nil
        }
        // Built here, on the main actor, so the whole batch describes one moment of the store.
        let batch = nextBatch(for: syncEngine, context: context)
        guard !batch.changes.isEmpty else { return nil }
        let records = batch.records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batch.changes) { recordID in
            records[recordID]
        }
    }
}
