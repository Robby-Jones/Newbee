import CloudKit
import Foundation
import NewbeeKit

/// Everything sync keeps between launches: CloudKit's place in each database, the ledger, and
/// which log this phone syncs with (docs/ICLOUD_SYNC.md).
///
/// It can always be rebuilt. Without it the phone compares its feeds with iCloud again, and where
/// both have the same feed the one changed last wins.
struct CloudSyncState: Codable {
    /// A CloudKit zone, in a form that can be saved.
    struct Zone: Codable, Equatable {
        var zoneName: String
        var ownerName: String

        init(_ id: CKRecordZone.ID) {
            zoneName = id.zoneName
            ownerName = id.ownerName
        }

        var id: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }
    }

    /// `CKSyncEngine`'s own state for the parent's private database, and for the shared one.
    var privateEngine: CKSyncEngine.State.Serialization?
    var sharedEngine: CKSyncEngine.State.Serialization?
    var ledger = SyncLedger()
    /// The other parent's zone, once this parent has joined their shared log. `nil`: this phone
    /// syncs with its own zone.
    var joinedZone: Zone?
    /// Whether this parent's own zone is known to exist in iCloud.
    var ownZoneExists = false
}

/// Reads and writes `CloudSyncState` as one file in the App Group container.
struct CloudSyncStateFile {
    let url: URL

    /// `<App Group>/Library/Application Support/CloudSync.plist`, next to the store.
    static func standard() throws -> CloudSyncStateFile {
        let storeURL = try PersistenceController.storeURL()
        return CloudSyncStateFile(url: storeURL.deletingLastPathComponent().appending(path: "CloudSync.plist"))
    }

    /// A missing or unreadable file means starting over, which is always safe.
    func load() -> CloudSyncState {
        guard let data = try? Data(contentsOf: url),
              let state = try? PropertyListDecoder().decode(CloudSyncState.self, from: data) else {
            return CloudSyncState()
        }
        return state
    }

    func save(_ state: CloudSyncState) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        // Readable while the phone is locked, like the store: Lock Screen buttons change feeds.
        try encoder.encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
