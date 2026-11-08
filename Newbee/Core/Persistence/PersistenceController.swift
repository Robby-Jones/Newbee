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

    static func makeContainer(_ storage: Storage) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NewbeeSchemaV1.self)
        let configuration: ModelConfiguration
        switch storage {
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .file(let url):
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        case .appGroup:
            let url = try storeURL()
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: NewbeeMigrationPlan.self,
                configurations: configuration
            )
            // SQLite creates the -wal and -shm files on open, so protect them once they exist.
            allowAccessWhileLocked(storeFilesFor: url)
            return container
        }
        return try ModelContainer(for: schema, migrationPlan: NewbeeMigrationPlan.self, configurations: configuration)
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
