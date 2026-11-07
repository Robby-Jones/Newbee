import SwiftUI
import SwiftData

@main
struct NewbeeApp: App {
    private let dependencies = AppDependencies.shared
    @State private var sessionModel = NewbeeApp.makeSessionModel()

    var body: some Scene {
        WindowGroup {
            if let container = dependencies.modelContainer {
                RootView(sessionModel: sessionModel)
                    .modelContainer(container)
            } else {
                StoreErrorView(error: dependencies.storeError)
            }
        }
    }

    /// Integration point for the session engine: replace the stand-in with
    /// `FeedingSessionUIModel(controller: <the shared FeedingSessionManager>)` once it lands.
    /// Until then Debug builds use an in-memory controller (nothing is saved) so the timer UI
    /// can be tried, and Release builds hide the feeding UI.
    private static func makeSessionModel() -> FeedingSessionUIModel? {
        #if DEBUG
        return FeedingSessionUIModel(controller: PreviewSessionController())
        #else
        return nil
        #endif
    }
}
