import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
enum PersistenceController {
    enum Storage {
        /// The on-disk store in the App Group container (shared with extensions).
        case appGroup
        /// An in-memory store for previews, UI tests and integration tests.
        case inMemory
        /// A store at a specific file, used by tests that simulate the app being terminated
        /// and relaunched on the same data.
        case file(URL)
    }

    /// The opened store, and whether it syncs with iCloud.
    struct OpenedStore {
        let container: ModelContainer
        /// The iCloud container the store syncs with, or `nil` when it stays on this device.
        let cloudKitContainerID: String?
        /// Why the store couldn't be opened with iCloud sync, if it was meant to be.
        let cloudKitError: Error?
    }

    static func makeContainer(_ storage: Storage) throws -> ModelContainer {
        try open(storage).container
    }

    /// Opens the store. The App Group store syncs with the private database of the parent's
    /// iCloud account when the build has an iCloud container (docs/ARCHITECTURE.md, ADR-011).
    /// Every other store stays on the device.
    static func open(_ storage: Storage, cloudKitContainerID: String? = AppConfiguration.cloudKitContainerID) throws -> OpenedStore {
        let schema = Schema(versionedSchema: NewbeeSchemaV3.self)
        switch storage {
        case .inMemory:
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return OpenedStore(container: try makeContainer(schema, configuration), cloudKitContainerID: nil, cloudKitError: nil)
        case .file(let url):
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            return OpenedStore(container: try makeContainer(schema, configuration), cloudKitContainerID: nil, cloudKitError: nil)
        case .appGroup:
            let url = try storeURL()
            var cloudKitError: Error?
            var opened: OpenedStore?
            if let cloudKitContainerID {
                do {
                    let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .private(cloudKitContainerID))
                    opened = OpenedStore(container: try makeContainer(schema, configuration), cloudKitContainerID: cloudKitContainerID, cloudKitError: nil)
                } catch {
                    // Feeds must stay usable, so fall back to the same store without sync. Settings
                    // shows the reason. The next launch tries iCloud again.
                    cloudKitError = error
                }
            }
            if opened == nil {
                let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                opened = OpenedStore(container: try makeContainer(schema, configuration), cloudKitContainerID: nil, cloudKitError: cloudKitError)
            }
            // SQLite creates the -wal and -shm files on open, so protect them once they exist.
            allowAccessWhileLocked(storeFilesFor: url)
            return opened!
        }
    }

    private static func makeContainer(_ schema: Schema, _ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: NewbeeMigrationPlan.self, configurations: configuration)
    }

    /// `<App Group>/Library/Application Support/Newbee.store`
    static func storeURL() throws -> URL {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupID
        ) else {
            throw PersistenceError.appGroupUnavailable(AppConfiguration.appGroupID)
        }
        let directory = group.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Newbee.store")
        allowAccessWhileLocked(directory)
        allowAccessWhileLocked(storeFilesFor: url)
        return url
    }

    /// Lock Screen and Dynamic Island buttons run their intents in the app process while the
    /// phone may be locked. With `.complete` protection the store would be unreadable then and
    /// the tap would fail, so the store uses `.completeUntilFirstUserAuthentication`: encrypted
    /// until the first unlock after a restart, readable while locked after that. The file
    /// protection class is the iOS default, but setting it explicitly keeps it that way if a
    /// stricter default is ever set on the app.
    static func allowAccessWhileLocked(storeFilesFor storeURL: URL) {
        let path = storeURL.path(percentEncoded: false)
        for suffix in ["", "-wal", "-shm"] {
            let fileURL = URL(filePath: path + suffix)
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                allowAccessWhileLocked(fileURL)
            }
        }
    }

    private static func allowAccessWhileLocked(_ url: URL) {
        #if os(iOS)
        // Best effort: a failure leaves the existing class, which is no worse than before.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        #endif
    }
}

enum PersistenceError: LocalizedError {
    case appGroupUnavailable(String)
    case storeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let id):
            "The shared app container (\(id)) is unavailable. Check the App Group entitlement."
        case .storeUnavailable(let reason):
            "Your feeding data couldn't be opened: \(reason)"
        }
    }
}
