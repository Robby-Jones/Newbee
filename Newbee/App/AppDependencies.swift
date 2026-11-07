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

    /// Keeps the Live Activity in step with the session. A no-op until `LiveActivityCoordinator`
    /// is wired in here.
    let liveActivity: any LiveActivitySyncing
    /// The single owner of the active feeding session (docs/TIMER_ENGINE.md).
    let sessionManager: FeedingSessionManager
    /// Launch, foreground and clock-change reconciliation.
    let recovery: RecoveryCoordinator
    /// Shared by recovery and the Live Activity's "Still feeding?" hint so both agree on thresholds.
    let recoveryPolicy: RecoveryPolicy

    init(
        clock: any AppClock = SystemClock(),
        storage: PersistenceController.Storage? = nil,
        liveActivity: (any LiveActivitySyncing)? = nil
    ) {
        self.clock = clock
        let resolvedStorage = storage ?? (AppConfiguration.isUITesting ? .inMemory : .appGroup)
        let container: ModelContainer?
        let error: Error?
        do {
            container = try PersistenceController.makeContainer(resolvedStorage)
            error = nil
        } catch let openError {
            container = nil
            error = openError
        }
        modelContainer = container
        storeError = error

        let repository: any FeedingRepository
        if let container {
            repository = SwiftDataFeedingRepository(container: container)
        } else {
            repository = UnavailableFeedingRepository(reason: error?.localizedDescription ?? "unknown error")
        }

        // One policy for recovery and for the Live Activity's "Still feeding?" hint.
        let policy = RecoveryPolicy()
        let activity = liveActivity ?? NoLiveActivities()
        let manager = FeedingSessionManager(repository: repository, clock: clock, liveActivity: activity)
        recoveryPolicy = policy
        self.liveActivity = activity
        sessionManager = manager
        recovery = RecoveryCoordinator(manager: manager, policy: policy)
    }
}
