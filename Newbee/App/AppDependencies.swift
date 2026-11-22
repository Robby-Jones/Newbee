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
    /// The baby's profile photo (Settings, Home).
    let babyPhoto: BabyPhotoStore
    /// iCloud sync status, and the signal that another device's changes arrived.
    let cloudSync: CloudSyncMonitor
    /// Settings → iCloud → "Sync with iCloud": off on a fresh install. `nil` when this run
    /// doesn't sync.
    let cloudSyncSwitch: CloudSyncSwitch?
    /// Syncs feeds and the baby profile with iCloud. `nil` when this run doesn't sync (tests,
    /// previews, a build without an iCloud container).
    let cloudEngine: CloudSyncEngine?
    /// Sharing the log with the other parent. `nil` whenever `cloudEngine` is.
    let cloudSharing: CloudSharing?
    /// Who is on duty tonight (docs/NIGHT_SHIFT.md).
    let nightShift: NightShiftModel

    init(
        clock: any AppClock = SystemClock(),
        storage: PersistenceController.Storage? = nil,
        liveActivity: (any LiveActivitySyncing)? = nil,
        notifications: (any NotificationClient)? = nil,
        alarms: (any NightAlarmClient)? = nil,
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
        let isAppStore: Bool
        if case .appGroup = resolvedStorage { isAppStore = true } else { isAppStore = false }
        // Only the real store syncs, and only in a build that has an iCloud container.
        let cloudKitContainerID = isAppStore && container != nil ? AppConfiguration.cloudKitContainerID : nil
        let userDefaults = defaults ?? AppPreferences.makeDefaults()
        let syncSwitch = cloudKitContainerID == nil ? nil : CloudSyncSwitch(
            defaults: userDefaults,
            isExistingInstall: Self.isExistingInstall(defaults: userDefaults)
        )
        cloudSyncSwitch = syncSwitch
        let cloudSync = CloudSyncMonitor(containerID: cloudKitContainerID, isEnabled: syncSwitch?.isOn ?? false)
        self.cloudSync = cloudSync
        let nightShiftStore = NightShiftStore(defaults: userDefaults)
        let engine: CloudSyncEngine?
        let sharing: CloudSharing?
        if let cloudKitContainerID, let container, let file = try? CloudSyncStateFile.standard() {
            let cloudEngine = CloudSyncEngine(
                containerID: cloudKitContainerID, modelContainer: container, nightShift: nightShiftStore,
                monitor: cloudSync, file: file, clock: clock
            )
            engine = cloudEngine
            sharing = CloudSharing(engine: cloudEngine, modelContainer: container)
        } else {
            engine = nil
            sharing = nil
        }
        cloudEngine = engine
        cloudSharing = sharing
        if let container, ScreenshotSampleData.isRequested {
            ScreenshotSampleData.seed(into: container, clock: clock)
        }

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
        // Settings follow the parent's iCloud account whenever feeds do.
        let preferences = AppPreferences(
            defaults: userDefaults,
            cloud: cloudKitContainerID == nil ? nil : NSUbiquitousKeyValueStore.default,
            cloudIsOn: syncSwitch?.isOn ?? false
        )
        self.preferences = preferences

        let isInMemory: Bool
        if case .inMemory = resolvedStorage { isInMemory = true } else { isInMemory = false }
        // Only the real store takes over a photo file saved by builds before schema V3.
        babyPhoto = BabyPhotoStore(
            container: container,
            legacyDirectory: isAppStore ? BabyPhotoStore.legacyDirectory : nil,
            liveActivityAvatarURL: isAppStore ? LiveActivityAvatar.fileURL : nil
        )
        // Only the real app rings alarms.
        let nightAlarms: any NightAlarmClient = alarms ?? (isAppStore ? SystemNightAlarmClient() : NoNightAlarmClient())
        let reminders = ReminderScheduler(
            preferences: preferences,
            feedingRepository: repository,
            bottleRepository: bottleRepository,
            // Only the real store notifies: UI tests, previews and test stores never prompt.
            client: notifications ?? (isAppStore ? SystemNotificationClient() : NoNotificationClient()),
            clock: clock,
            alarms: nightAlarms
        )
        self.reminders = reminders
        let nightShift = NightShiftModel(
            store: nightShiftStore, preferences: preferences, sharing: sharing, engine: engine,
            reminders: reminders, alarms: nightAlarms, modelContainer: container, clock: clock
        )
        self.nightShift = nightShift
        // The shift decides which phone rings, so every change to it replans the reminders.
        reminders.nightShift = { [nightShift] in nightShift.reminderContext() }
        nightShiftStore.onChange = { [reminders] in
            Task { await reminders.reschedule() }
        }
        nightShiftStore.onLocalChange = { [engine] in
            engine?.localDataDidChange()
        }

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
        (activity as? LiveActivityCoordinator)?.babyName = { [container] in
            guard let context = container?.mainContext else { return "" }
            return Baby.primary(in: context)?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        (activity as? LiveActivityCoordinator)?.countFrom = { [preferences] in
            preferences.reminders.basis
        }
        (activity as? LiveActivityCoordinator)?.theme = { [preferences] in
            preferences.colorTheme
        }
        (activity as? LiveActivityCoordinator)?.cardColor = { [preferences] in
            preferences.liveActivityColor
        }
        (activity as? LiveActivityCoordinator)?.islandIcon = { [preferences] in
            preferences.islandIcon
        }
        (activity as? LiveActivityCoordinator)?.startingSide = { [preferences] in
            preferences.startingSide
        }
        // Bottles too: the Live Activity counts from the latest feed of either kind.
        let manager = FeedingSessionManager(
            repository: repository, clock: clock, liveActivity: activity, reminders: reminders, bottles: bottleRepository
        )
        manager.startingSide = preferences.startingSide
        recoveryPolicy = policy
        self.liveActivity = activity
        sessionManager = manager
        recovery = RecoveryCoordinator(manager: manager, policy: policy)
    }

    /// Whether the app ran on this device before "Sync with iCloud" existed, when sync was always
    /// on: onboarding was done, or sync had saved its state.
    static func isExistingInstall(defaults: UserDefaults) -> Bool {
        if defaults.bool(forKey: AppPreferences.Key.onboardingComplete) { return true }
        guard let file = try? CloudSyncStateFile.standard() else { return false }
        return FileManager.default.fileExists(atPath: file.url.path)
    }

    /// Routes Lock Screen and Dynamic Island buttons to `sessionManager`. Called from
    /// `NewbeeApp.init`, which runs even when iOS launches the app in the background just to
    /// perform a Live Activity intent (a view `.task` might never run then).
    func registerLiveActivityIntents() {
        LiveActivityIntentRouter.register(sessionManager)
    }
}
