import Foundation
import NewbeeKit
import SwiftData
import SwiftUI

@main
struct NewbeeApp: App {
    private let dependencies = AppDependencies.shared
    @State private var sessionModel = NewbeeApp.makeSessionModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let container = dependencies.modelContainer {
                let recovery = dependencies.recovery
                RootView(sessionModel: sessionModel)
                    .modelContainer(container)
                    // Restore any session interrupted by termination, reboot or a clock change
                    // (docs/TIMER_ENGINE.md §5). Reconciling is idempotent, so overlapping
                    // triggers are harmless.
                    .task { await recovery.reconcile() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            Task { await recovery.reconcile() }
                        }
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
