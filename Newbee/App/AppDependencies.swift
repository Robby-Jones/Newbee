import Foundation
import NewbeeKit
import NewbeeShared
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

    /// Keeps the Live Activity in step with the session: `LiveActivityCoordinator` in the app,
    /// a no-op for in-memory stores (previews, UI and integration tests).
    let liveActivity: any LiveActivitySyncing
    /// The single owner of the active feeding session (docs/TIMER_ENGINE.md).
    let sessionManager: FeedingSessionManager
    /// Launch, foreground and clock-change reconciliation.
    let recovery: RecoveryCoordinator
    /// Shared by recovery and the Live Activity's "Still feeding?" hint so both agree on thresholds.
    let recoveryPolicy: RecoveryPolicy
    /// Bottle feeds: instant entries, separate from the breastfeeding session manager.
    let bottleLog: BottleLog
    /// Pumping sessions: entered by hand like bottles, never counted as feeds.
    let pumpLog: PumpLog
    /// Units, presets, reminders and appearance (App Group `UserDefaults`).
    let preferences: AppPreferences
    /// Feed-due and "Still feeding?" local notifications.
    let reminders: ReminderScheduler

    init(
        clock: any AppClock = SystemClock(),
        storage: PersistenceController.Storage? = nil,
        liveActivity: (any LiveActivitySyncing)? = nil,
        notifications: (any NotificationClient)? = nil,
        defaults: UserDefaults? = nil
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
        let bottleRepository: any BottleRepository
        let pumpRepository: any PumpRepository
        if let container {
            repository = SwiftDataFeedingRepository(container: container)
            bottleRepository = SwiftDataBottleRepository(container: container)
            pumpRepository = SwiftDataPumpRepository(container: container)
        } else {
            let reason = error?.localizedDescription ?? "unknown error"
            repository = UnavailableFeedingRepository(reason: reason)
            bottleRepository = UnavailableBottleRepository(reason: reason)
            pumpRepository = UnavailablePumpRepository(reason: reason)
        }
        bottleLog = BottleLog(repository: bottleRepository, clock: clock)
        pumpLog = PumpLog(repository: pumpRepository, clock: clock)
        let preferences = AppPreferences(defaults: defaults ?? AppPreferences.makeDefaults())
        self.preferences = preferences

        let isInMemory: Bool
        if case .inMemory = resolvedStorage { isInMemory = true } else { isInMemory = false }
        let isAppStore: Bool
        if case .appGroup = resolvedStorage { isAppStore = true } else { isAppStore = false }
        let reminders = ReminderScheduler(
            preferences: preferences,
            feedingRepository: repository,
            bottleRepository: bottleRepository,
            // Only the real store notifies: UI tests, previews and test stores never prompt.
            client: notifications ?? (isAppStore ? SystemNotificationClient() : NoNotificationClient()),
            clock: clock
        )
        self.reminders = reminders

        // One policy for recovery, the Live Activity's "Still feeding?" hint and the notification,
        // at the threshold chosen in Settings (read at launch).
        let policy = RecoveryPolicy(stillFeedingThreshold: preferences.reminders.stillFeedingThreshold)
        let activity: any LiveActivitySyncing
        if let liveActivity {
            activity = liveActivity
        } else if isInMemory {
            activity = NoLiveActivities()
        } else {
            // Same clock as the manager; stale hint at the same threshold as the recovery prompt.
            activity = LiveActivityCoordinator(
                client: ActivityKitClient(),
                clock: clock,
                planner: LiveActivityPlanner(staleAfter: policy.effectiveThreshold)
            )
        }
        // The Lock Screen activity follows the app's Light / Dark / System setting.
        (activity as? LiveActivityCoordinator)?.appearance = { [preferences] in
            LiveActivityAppearance(preferences.appearance)
        }
        (activity as? LiveActivityCoordinator)?.countFrom = { [preferences] in
            preferences.reminders.basis
        }
        // Bottles too: the Live Activity counts from the latest feed of either kind.
        let manager = FeedingSessionManager(
            repository: repository, clock: clock, liveActivity: activity, reminders: reminders, bottles: bottleRepository
        )
        recoveryPolicy = policy
        self.liveActivity = activity
        sessionManager = manager
        recovery = RecoveryCoordinator(manager: manager, policy: policy)
    }

    /// Routes Lock Screen and Dynamic Island buttons to `sessionManager`. Called from
    /// `NewbeeApp.init`, which runs even when iOS launches the app in the background just to
    /// perform a Live Activity intent (a view `.task` might never run then).
    func registerLiveActivityIntents() {
        LiveActivityIntentRouter.register(sessionManager)
    }
}
