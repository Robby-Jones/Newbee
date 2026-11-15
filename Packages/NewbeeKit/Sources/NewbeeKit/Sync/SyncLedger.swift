import Foundation

/// What a scan of the local store found for one item.
public struct SyncLocalItem: Sendable, Hashable {
    /// `Fingerprint` of the item as stored now.
    public var fingerprint: Int64
    /// The item's own idea of when it last changed. Only used the first time sync sees the item.
    public var changedAt: Date

    public init(fingerprint: Int64, changedAt: Date) {
        self.fingerprint = fingerprint
        self.changedAt = changedAt
    }
}

/// What still has to be sent to the server.
public struct SyncPending: Sendable, Equatable {
    public var saves: Set<SyncKey>
    public var deletes: Set<SyncKey>

    public init(saves: Set<SyncKey> = [], deletes: Set<SyncKey> = []) {
        self.saves = saves
        self.deletes = deletes
    }

    public var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
}

/// Sync's memory of each item: what this device holds, what the server is known to hold, and when
/// the content last changed (docs/ICLOUD_SYNC.md).
///
/// The local store stays the source of truth. Nothing has to tell sync about a change: comparing
/// the store with the ledger (`scan`) finds every insert, edit and delete, whichever code made it.
/// "Pending" is never stored, only derived, so a crash or a failed send can't lose a change.
public struct SyncLedger: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        /// When the content last changed, on the device that changed it.
        public var changedAt: Date
        /// Fingerprint of the item in the local store. `nil`: deleted here, server not told yet.
        public var local: Int64?
        /// Fingerprint of what the server holds. `nil`: not known to be on the server.
        public var synced: Int64?
        /// The server's bookkeeping for its copy, needed to save over it.
        public var systemFields: Data?

        public init(changedAt: Date, local: Int64?, synced: Int64?, systemFields: Data?) {
            self.changedAt = changedAt
            self.local = local
            self.synced = synced
            self.systemFields = systemFields
        }

        /// The server has, or may have, a copy.
        var isKnownToServer: Bool { synced != nil || systemFields != nil }
    }

    public enum IncomingDecision: Sendable, Equatable {
        /// Take the server's version.
        case apply
        /// Both sides hold the same content already.
        case same
        /// This device has a newer change that hasn't been sent yet. Keep it and send it.
        case keepLocal
    }

    public private(set) var entries: [SyncKey: Entry]

    public init(entries: [SyncKey: Entry] = [:]) {
        self.entries = entries
    }

    public subscript(key: SyncKey) -> Entry? { entries[key] }

    // MARK: - Local changes

    /// Brings the ledger in line with the local store. An item whose content differs from last
    /// time was just changed on this device, so its change time becomes `now`.
    public mutating func scan(local: [SyncKey: SyncLocalItem], now: Date) {
        for (key, item) in local {
            if var entry = entries[key] {
                guard entry.local != item.fingerprint else { continue }
                entry.local = item.fingerprint
                if entry.synced != item.fingerprint {
                    entry.changedAt = now
                }
                entries[key] = entry
            } else {
                // First sight: trust the item's own timestamp, so data that predates sync (or a
                // rebuilt ledger) doesn't pose as a fresh edit and win conflicts it shouldn't.
                entries[key] = Entry(changedAt: min(item.changedAt, now), local: item.fingerprint, synced: nil, systemFields: nil)
            }
        }
        for (key, entry) in entries where local[key] == nil && entry.local != nil {
            if entry.isKnownToServer {
                entries[key]?.local = nil
                entries[key]?.changedAt = now
            } else {
                entries[key] = nil
            }
        }
    }

    /// Everything the server hasn't got yet.
    public var pending: SyncPending {
        var pending = SyncPending()
        for (key, entry) in entries {
            if entry.local == nil {
                pending.deletes.insert(key)
            } else if entry.local != entry.synced {
                pending.saves.insert(key)
            }
        }
        return pending
    }

    public func needsSave(_ key: SyncKey) -> Bool {
        guard let entry = entries[key], let local = entry.local else { return false }
        return local != entry.synced
    }

    public func needsDelete(_ key: SyncKey) -> Bool {
        guard let entry = entries[key] else { return false }
        return entry.local == nil
    }

    // MARK: - Changes from the server

    /// What to do with a version of `key` that came from the server. Call `scan` first.
    public func decide(incoming key: SyncKey, fingerprint: Int64, changedAt: Date) -> IncomingDecision {
        guard let entry = entries[key] else { return .apply }
        guard let local = entry.local else {
            // Deleted here, changed there: the later one wins.
            return changedAt >= entry.changedAt ? .apply : .keepLocal
        }
        if local == fingerprint { return .same }
        // Nothing unsent here, so the server's version is simply newer.
        if local == entry.synced { return .apply }
        // Both changed. The later change wins; the server wins a tie so every device agrees.
        return changedAt >= entry.changedAt ? .apply : .keepLocal
    }

    /// Whether to delete the local item now that the server deleted its copy. An item with an
    /// unsent edit is kept and sent again: an edit is never thrown away by a delete elsewhere.
    public func shouldDeleteLocal(afterServerDeleted key: SyncKey) -> Bool {
        guard let entry = entries[key], let local = entry.local, entry.isKnownToServer else { return false }
        return local == entry.synced
    }

    /// The server's version was written to the local store, which now holds `fingerprint`.
    public mutating func applied(_ key: SyncKey, fingerprint: Int64, changedAt: Date, systemFields: Data?) {
        entries[key] = Entry(changedAt: changedAt, local: fingerprint, synced: fingerprint, systemFields: systemFields)
    }

    /// The server's version turned out to match the local item.
    public mutating func matched(_ key: SyncKey, fingerprint: Int64, changedAt: Date, systemFields: Data?) {
        entries[key] = Entry(changedAt: changedAt, local: fingerprint, synced: fingerprint, systemFields: systemFields)
    }

    /// The local version is kept over the server's. Remember the server's bookkeeping so the next
    /// save is accepted.
    public mutating func keptLocal(_ key: SyncKey, systemFields: Data?) {
        entries[key]?.systemFields = systemFields
        entries[key]?.synced = nil
    }

    /// The server no longer has `key` (deleted there, or never arrived).
    public mutating func serverLost(_ key: SyncKey) {
        guard let entry = entries[key] else { return }
        if entry.local == nil {
            entries[key] = nil
        } else {
            entries[key]?.synced = nil
            entries[key]?.systemFields = nil
        }
    }

    /// The local item was deleted because the server deleted its copy.
    public mutating func removed(_ key: SyncKey) {
        entries[key] = nil
    }

    // MARK: - Results of sending

    /// The server accepted a save of content with `fingerprint`.
    public mutating func saved(_ key: SyncKey, fingerprint: Int64, systemFields: Data?) {
        guard entries[key] != nil else { return }
        entries[key]?.synced = fingerprint
        entries[key]?.systemFields = systemFields
    }

    /// The server deleted `key` as asked.
    public mutating func deleted(_ key: SyncKey) {
        serverLost(key)
    }

    /// Forgets everything known about the server while keeping each item's change time: used when
    /// syncing starts over against another zone or account. Every local item is then pending
    /// again, and where the server already has one the later change wins as usual.
    public mutating func forgetServer() {
        for (key, entry) in entries {
            if entry.local == nil {
                entries[key] = nil
            } else {
                entries[key]?.synced = nil
                entries[key]?.systemFields = nil
            }
        }
    }
}
