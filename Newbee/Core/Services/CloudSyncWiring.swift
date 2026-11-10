import Foundation
import SwiftData

/// iCloud sync at the app level (docs/ICLOUD_SYNC.md).
extension AppDependencies {
    /// Starts watching iCloud for feeds and settings from the parent's other devices. Called
    /// from `NewbeeApp.init`, so it also runs when iOS launches the app in the background to
    /// deliver changes.
    func startCloudSync() {
        guard cloudSync.containerID != nil else { return }
        cloudSync.onImport = { [weak self] in
            guard let self else { return }
            Task { await self.cloudSyncDidImport() }
        }
        cloudSync.start()
        preferences.startCloudSync()
        mergeDuplicateBabies()
    }

    /// Changes from another device arrived. `@Query` views update on their own; the rest is
    /// refreshed here: duplicate baby profiles, the photo, and the timer with its Live Activity
    /// and reminders (another device may have started or ended a feed).
    func cloudSyncDidImport() async {
        mergeDuplicateBabies()
        babyPhoto.reload()
        await sessionManager.reload()
    }

    private func mergeDuplicateBabies() {
        guard let context = modelContainer?.mainContext else { return }
        if (try? BabyMerge.mergeDuplicates(in: context)) == true {
            babyPhoto.reload()
        }
    }
}
