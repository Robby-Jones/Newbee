import Foundation

/// The local store, as sync sees it. The app implements it over SwiftData; tests use a dictionary.
@MainActor
public protocol SyncLocalStore: AnyObject {
    /// Every item that syncs, as stored right now.
    func items() throws -> [SyncKey: SyncLocalItem]

    /// The content to send for `key`, or `nil` if the item is gone.
    func content(for key: SyncKey) throws -> SyncContent?

    /// Inserts or replaces each item and commits, all or nothing. Returns the fingerprint of each
    /// item as it is stored afterwards. Content this build can't read is skipped and left out of
    /// the result.
    func apply(_ contents: [SyncKey: SyncContent]) throws -> [SyncKey: Int64]

    /// Deletes each item and commits, all or nothing. Missing items aren't an error.
    func delete(_ keys: [SyncKey]) throws
}

/// Decides what to send and what to do with what arrives. It knows nothing about CloudKit: the
/// app's `CloudSyncEngine` moves records, and this keeps the store and the ledger right
/// (docs/ICLOUD_SYNC.md).
@MainActor
public final class SyncCore {
    public private(set) var ledger: SyncLedger
    private let store: any SyncLocalStore
    private let clock: any AppClock
    /// The fingerprint of each record as it was handed out for sending, so an accepted save is
    /// recorded as exactly the content that was sent.
    private var sent: [SyncKey: Int64] = [:]

    public init(store: any SyncLocalStore, ledger: SyncLedger = SyncLedger(), clock: any AppClock = SystemClock()) {
        self.store = store
        self.ledger = ledger
        self.clock = clock
    }

    // MARK: - Sending

    /// Compares the store with the ledger and returns everything the server hasn't got yet.
    @discardableResult
    public func scan() throws -> SyncPending {
        ledger.scan(local: try store.items(), now: clock.now)
        return ledger.pending
    }

    /// The record to save for `key`, or `nil` when there is nothing to save any more.
    public func outgoingRecord(for key: SyncKey) throws -> SyncRecord? {
        guard ledger.needsSave(key), let entry = ledger[key], let fingerprint = entry.local,
              let content = try store.content(for: key) else { return nil }
        sent[key] = fingerprint
        return SyncRecord(key: key, changedAt: entry.changedAt, content: content, systemFields: entry.systemFields)
    }

    public func needsDelete(_ key: SyncKey) -> Bool {
        ledger.needsDelete(key)
    }

    /// The server accepted the save of `record`.
    public func didSave(_ record: SyncRecord) {
        let fingerprint = sent.removeValue(forKey: record.key)
            ?? SyncCodec.fingerprint(of: record.content, kind: record.key.kind)
        guard let fingerprint else { return }
        ledger.saved(record.key, fingerprint: fingerprint, systemFields: record.systemFields)
    }

    /// The server deleted `key`, or didn't have it.
    public func didDelete(_ key: SyncKey) {
        ledger.deleted(key)
    }

    /// The server no longer has the record this device tried to save over. It is sent again as new.
    public func serverLost(_ key: SyncKey) {
        sent[key] = nil
        ledger.serverLost(key)
    }

    // MARK: - Receiving

    /// Takes in records the server changed or deleted, including the server's version handed back
    /// when a save conflicts. Returns true if the local store changed.
    @discardableResult
    public func receive(modifications: [SyncRecord] = [], deletions: [SyncKey] = []) throws -> Bool {
        guard !modifications.isEmpty || !deletions.isEmpty else { return false }
        // Edits made since the last scan must count as local changes, not be overwritten blindly.
        try scan()

        var toApply: [SyncKey: SyncRecord] = [:]
        for record in modifications {
            guard let fingerprint = SyncCodec.fingerprint(of: record.content, kind: record.key.kind) else { continue }
            sent[record.key] = nil
            switch ledger.decide(incoming: record.key, fingerprint: fingerprint, changedAt: record.changedAt) {
            case .apply:
                toApply[record.key] = record
            case .same:
                toApply[record.key] = nil
                ledger.matched(record.key, fingerprint: fingerprint, changedAt: record.changedAt, systemFields: record.systemFields)
            case .keepLocal:
                toApply[record.key] = nil
                ledger.keptLocal(record.key, systemFields: record.systemFields)
            }
        }
        var toDelete: [SyncKey] = []
        for key in deletions where toApply[key] == nil {
            if ledger.shouldDeleteLocal(afterServerDeleted: key) {
                toDelete.append(key)
            } else {
                ledger.serverLost(key)
            }
        }

        if !toApply.isEmpty {
            let stored = try store.apply(toApply.mapValues(\.content))
            for (key, record) in toApply {
                guard let fingerprint = stored[key] else { continue }
                ledger.applied(key, fingerprint: fingerprint, changedAt: record.changedAt, systemFields: record.systemFields)
            }
        }
        if !toDelete.isEmpty {
            try store.delete(toDelete)
            for key in toDelete {
                ledger.removed(key)
            }
        }
        return !toApply.isEmpty || !toDelete.isEmpty
    }

    // MARK: - Starting over

    /// Syncing starts over against another zone or account: every local item is sent again, and
    /// where the server already has one the later change wins.
    public func forgetServer() {
        sent = [:]
        ledger.forgetServer()
    }
}
