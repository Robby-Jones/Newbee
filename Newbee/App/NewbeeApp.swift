import Foundation
import NewbeeKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct NewbeeApp: App {
    private let dependencies = AppDependencies.shared
    @State private var sessionModel = NewbeeApp.makeSessionModel()
    @State private var bottleModel = BottleLogUIModel(
        log: AppDependencies.shared.bottleLog,
        preferences: AppDependencies.shared.preferences,
        // A bottle counts as the last feed for reminders and the Live Activity's count.
        onChange: { logged in
            Task { await AppDependencies.shared.reminders.reschedule() }
            // A newly logged bottle that is the latest feed brings the Live Activity back if it
            // was swiped away or expired.
            Task { await AppDependencies.shared.sessionManager.bottlesDidChange(logged: logged) }
        }
    )
    @State private var pumpModel = PumpLogUIModel(
        log: AppDependencies.shared.pumpLog,
        preferences: AppDependencies.shared.preferences
    )
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before any scene exists: Live Activity intents can launch the app in the background.
        dependencies.registerLiveActivityIntents()
        // Also before any scene: iOS can launch the app in the background to deliver iCloud changes.
        dependencies.startCloudSync()
        // Reminders show as banners while the app is open, too.
        UNUserNotificationCenter.current().delegate = ForegroundNotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            if let container = dependencies.modelContainer {
                let recovery = dependencies.recovery
                RootView(sessionModel: sessionModel, bottleModel: bottleModel, pumpModel: pumpModel)
                    .modelContainer(container)
                    .environment(dependencies.preferences)
                    .environment(dependencies.reminders)
                    .environment(dependencies.babyPhoto)
                    .environment(dependencies.cloudSync)
                    .environment(\.dataManagement, DataManagementActions(dependencies: dependencies))
                    // Restore any session interrupted by termination, reboot or a clock change
                    // (docs/TIMER_ENGINE.md §5). Reconciling is idempotent, so overlapping
                    // triggers are harmless.
                    .task { await recovery.reconcile() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            Task { await recovery.reconcile() }
                            // Today's bottle and pumping totals roll over at midnight.
                            bottleModel.refresh()
                            pumpModel.refresh()
                            // Picks up permission changes made in iOS Settings.
                            Task { await dependencies.reminders.reschedule() }
                        }
                    }
                    // Re-draws the Live Activity in the newly chosen Light / Dark / System look.
                    .onChange(of: dependencies.preferences.appearance) {
                        Task { await dependencies.sessionManager.reload() }
                    }
                    // Re-draws the since-last-feed count from the newly chosen start or end.
                    .onChange(of: dependencies.preferences.reminders.basis) {
                        Task { await dependencies.sessionManager.reload() }
                    }
                    // Feeds from another device can change today's bottle and pumping totals.
                    .onChange(of: dependencies.cloudSync.importCount) {
                        bottleModel.refresh()
                        pumpModel.refresh()
                    }
                    // Reminder settings changed on another device.
                    .onChange(of: dependencies.preferences.cloudChangeCount) {
                        Task { await dependencies.reminders.reschedule() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
                        Task { await recovery.reconcile() }
                    }
            } else {
                StoreErrorView(error: dependencies.storeError)
            }
        }
    }

    /// The timer UI drives the shared `FeedingSessionManager`, the same instance Live Activity
    /// intents use. UI tests (`-uiTesting`) get it on an in-memory store.
    private static func makeSessionModel() -> FeedingSessionUIModel? {
        FeedingSessionUIModel(controller: AppDependencies.shared.sessionManager)
    }
}
