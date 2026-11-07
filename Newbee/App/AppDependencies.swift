import Foundation
import NewbeeKit
import SwiftData

/// The app's composition root. One instance is shared by the UI and by App Intents
/// (which run in the app process), so every command goes through the same services.
@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    let clock: any AppClock
    /// `nil` if the store failed to open; the UI shows a recovery screen instead of resetting data.
    let modelContainer: ModelContainer?
    let storeError: Error?

    init(clock: any AppClock = SystemClock(), storage: PersistenceController.Storage? = nil) {
        self.clock = clock
        let resolvedStorage = storage ?? (AppConfiguration.isUITesting ? .inMemory : .appGroup)
        do {
            modelContainer = try PersistenceController.makeContainer(resolvedStorage)
            storeError = nil
        } catch {
            modelContainer = nil
            storeError = error
        }
    }
}
