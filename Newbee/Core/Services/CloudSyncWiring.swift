import Foundation
import SwiftData

/// iCloud sync at the app level (docs/ICLOUD_SYNC.md).
extension AppDependencies {
    /// Sets up iCloud sync, and starts it if "Sync with iCloud" is on: feeds with the parent's
    /// other devices (and the other parent once the log is shared), settings with the parent's
    /// other devices. Called from `NewbeeApp.init`, so it also runs when iOS launches the app in
    /// the background to deliver changes.
    func startCloudSync() {
        guard cloudSync.containerID != nil, let cloudSyncSwitch else { return }
        cloudSync.onImport = { [weak self] in
            guard let self else { return }
            Task { await self.cloudSyncDidImport() }
        }
        // The account is watched even with sync off: Settings says whether iCloud is there.
        cloudSync.start()
        if let cloudEngine, let cloudSharing {
            cloudEngine.onSharingChange = { [weak cloudSharing] in
                cloudSharing?.engineChangedSharing()
            }
            cloudEngine.onAccountChange = { [nightShift] in
                nightShift.forgetIdentity()
            }
        }
        cloudSyncSwitch.activate = { [weak self] in
            await self?.turnOnCloudSync()
        }
        cloudSyncSwitch.deactivate = { [weak self] in
            try await self?.turnOffCloudSync()
        }
        if cloudSyncSwitch.isOn {
            runCloudSync()
        }
    }

    /// Starts every part of sync. Settings were already merged when `AppPreferences` was made.
    private func runCloudSync() {
        preferences.startCloudSync()
        mergeDuplicateBabies()
        if let cloudEngine, let cloudSharing {
            cloudEngine.start()
            Task { await cloudSharing.refresh() }
            // Night Shift needs to know which of the two parents this is.
            Task { await nightShift.refreshIdentity() }
        }
    }

    /// The parent turned on "Sync with iCloud". Like a new device: settings already in iCloud
    /// replace this phone's, feeds on the phone are uploaded, and everything in iCloud is fetched
    /// and merged in (where both have the same feed, the one changed last wins).
    private func turnOnCloudSync() async {
        cloudSync.setEnabled(true)
        preferences.setCloudSync(true)
        runCloudSync()
        await cloudSync.refreshAccountStatus()
        await cloudEngine?.fetchAll()
        await cloudSyncDidImport()
    }

    /// The parent turned off "Sync with iCloud". Sharing ends first (the partner keeps every feed
    /// so far); if iCloud can't be reached for that, this throws and sync stays on. Feeds and
    /// settings stay on the phone, and what is in iCloud stays there.
    private func turnOffCloudSync() async throws {
        try await cloudSharing?.endBeforeTurningOffSync()
        cloudEngine?.stop()
        cloudSharing?.syncDidStop()
        preferences.setCloudSync(false)
        cloudSync.setEnabled(false)
        // Night Shift needs a partner on the log; without one each phone rings as usual.
        await reminders.reschedule()
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
