import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
enum PersistenceController {
    enum Storage {
        /// The on-disk store in the App Group container (shared with extensions).
        case appGroup
        /// An in-memory store for previews, UI tests and integration tests.
        case inMemory
    }

    static func makeContainer(_ storage: Storage) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NewbeeSchemaV1.self)
        let configuration: ModelConfiguration
        switch storage {
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .appGroup:
            configuration = ModelConfiguration(
                schema: schema,
                url: try storeURL(),
                cloudKitDatabase: .none
            )
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
        return directory.appending(path: "Newbee.store")
    }
}

enum PersistenceError: LocalizedError {
    case appGroupUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let id):
            "The shared app container (\(id)) is unavailable. Check the App Group entitlement."
        }
    }
}
