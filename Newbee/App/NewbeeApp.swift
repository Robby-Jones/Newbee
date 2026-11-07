import SwiftUI

@main
struct NewbeeApp: App {
    private let dependencies = AppDependencies.shared

    var body: some Scene {
        WindowGroup {
            if let container = dependencies.modelContainer {
                RootView()
                    .modelContainer(container)
            } else {
                StoreErrorView(error: dependencies.storeError)
            }
        }
    }
}
