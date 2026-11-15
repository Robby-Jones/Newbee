import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// iCloud sync pieces that run without iCloud: merging baby profiles, mirroring settings to
/// key-value storage, and the Settings status (docs/ICLOUD_SYNC.md). Feeds: `SyncStoreTests`.
@MainActor
@Suite("iCloud sync")
struct ICloudSyncTests {
    let now = Date(timeIntervalSince1970: 1_793_944_800)

    // MARK: - Baby merge

    private func insertBottle(baby: Baby?, at date: Date, in context: ModelContext) -> FeedingSession {
        let session = FeedingSession(kind: .bottle, status: .completed, startedAt: date, source: .manual)
        session.endedAt = date
        context.insert(session)
        session.baby = baby
        return session
    }

    /// Two devices each made a profile before their first sync. The older one is kept, filled in
    /// from the newer one, and every feed ends up on it.
    @Test func twoProfilesMergeIntoTheOldest() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let older = Baby(name: "", createdAt: now.addingTimeInterval(-3_600))
        let newer = Baby(name: "Ella", birthDate: now.addingTimeInterval(-10 * 86_400), createdAt: now)
        newer.photoData = Data([1, 2, 3])
        context.insert(older)
        context.insert(newer)
        let first = insertBottle(baby: older, at: now.addingTimeInterval(-1_800), in: context)
        let second = insertBottle(baby: newer, at: now.addingTimeInterval(-600), in: context)
        try context.save()

        #expect(try BabyMerge.mergeDuplicates(in: context))

        let babies = try context.fetch(FetchDescriptor<Baby>())
        #expect(babies.count == 1)
        let kept = try #require(babies.first)
        #expect(kept.id == older.id)
        #expect(kept.name == "Ella")
        #expect(kept.birthDate == now.addingTimeInterval(-10 * 86_400))
        #expect(kept.photoData == Data([1, 2, 3]))
        #expect(first.baby?.id == kept.id)
        #expect(second.baby?.id == kept.id)
        #expect(try context.fetchCount(FetchDescriptor<FeedingSession>()) == 2)
        // Nothing left to do the second time.
        #expect(try BabyMerge.mergeDuplicates(in: context) == false)
    }

    /// The kept profile's own name and birth date win.
    @Test func theKeptProfileKeepsItsOwnDetails() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let older = Baby(name: "Millie", createdAt: now.addingTimeInterval(-60))
        context.insert(older)
        context.insert(Baby(name: "Mil", createdAt: now))
        try context.save()

        try BabyMerge.mergeDuplicates(in: context)
        #expect(try context.fetch(FetchDescriptor<Baby>()).map(\.name) == ["Millie"])
    }

    /// A feed left without a baby (its baby was merged away on another device first) is attached
    /// to the kept baby.
    @Test func orphanedFeedsJoinTheBaby() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let baby = Baby(name: "Ella")
        context.insert(baby)
        let orphan = insertBottle(baby: nil, at: now, in: context)
        try context.save()

        #expect(try BabyMerge.mergeDuplicates(in: context))
        #expect(orphan.baby?.id == baby.id)
    }

    /// Every device must pick the same profile, even with identical creation times.
    @Test func everyDevicePicksTheSamePrimaryBaby() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let a = Baby(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, createdAt: now)
        let b = Baby(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, createdAt: now)
        context.insert(b)
        context.insert(a)
        try context.save()
        #expect(Baby.primary(in: context)?.id == a.id)
    }

    @Test func noBabyMeansNothingToMerge() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        _ = insertBottle(baby: nil, at: now, in: context)
        try context.save()
        #expect(try BabyMerge.mergeDuplicates(in: context) == false)
        #expect(try context.fetchCount(FetchDescriptor<Baby>()) == 0)
    }

    // MARK: - Settings

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ICloudSyncTests-\(UUID().uuidString)")!
    }

    @Test func changedSettingsAreSentToICloud() {
        let cloud = FakeCloudKeyValueStore()
        let preferences = AppPreferences(defaults: makeDefaults(), locale: Locale(identifier: "en_US"), cloud: cloud)
        preferences.volumeUnit = .milliliters
        preferences.bottlePresetsML = [60, 90, 120]
        preferences.reminders.isEnabled = true
        preferences.appearance = .dark
        preferences.onboardingComplete = true

        #expect(cloud.values[AppPreferences.Key.volumeUnit] as? String == VolumeUnit.milliliters.rawValue)
        #expect(cloud.values[AppPreferences.Key.bottlePresets] as? [Double] == [60, 90, 120])
        #expect(cloud.values[AppPreferences.Key.reminderEnabled] as? Bool == true)
        #expect(cloud.values[AppPreferences.Key.appearance] as? String == "dark")
        // Each device runs its own onboarding.
        #expect(cloud.values[AppPreferences.Key.onboardingComplete] == nil)
    }

    /// A new device takes the settings already in iCloud, and sends up those only it has.
    @Test func atLaunchICloudWinsAndLocalOnlySettingsAreKept() {
        let cloud = FakeCloudKeyValueStore()
        cloud.values[AppPreferences.Key.volumeUnit] = VolumeUnit.milliliters.rawValue
        let defaults = makeDefaults()
        defaults.set(VolumeUnit.fluidOunces.rawValue, forKey: AppPreferences.Key.volumeUnit)
        defaults.set([2.0, 3.0], forKey: AppPreferences.Key.pumpPresets)

        let preferences = AppPreferences(defaults: defaults, locale: Locale(identifier: "en_US"), cloud: cloud)
        #expect(preferences.volumeUnit == .milliliters)
        #expect(preferences.pumpPresetsML == [2.0, 3.0])
        #expect(cloud.values[AppPreferences.Key.pumpPresets] as? [Double] == [2.0, 3.0])
    }

    @Test func settingsChangedOnAnotherDeviceApplyWithoutEchoing() {
        let cloud = FakeCloudKeyValueStore()
        let preferences = AppPreferences(defaults: makeDefaults(), locale: Locale(identifier: "en_US"), cloud: cloud)
        preferences.bottlePresetsML = [60]
        cloud.setCount = 0

        cloud.values[AppPreferences.Key.bottlePresets] = [30.0, 45.0]
        cloud.values[AppPreferences.Key.appearance] = "light"
        preferences.applyCloudChange(
            keys: [AppPreferences.Key.bottlePresets, AppPreferences.Key.appearance],
            reason: NSUbiquitousKeyValueStoreServerChange
        )
        #expect(preferences.bottlePresetsML == [30.0, 45.0])
        #expect(preferences.appearance == .light)
        #expect(preferences.cloudChangeCount == 1)
        #expect(cloud.setCount == 0)

        // Removed on the other device ("Delete all data"): back to the default here too.
        cloud.values[AppPreferences.Key.bottlePresets] = nil
        preferences.applyCloudChange(keys: [AppPreferences.Key.bottlePresets], reason: NSUbiquitousKeyValueStoreServerChange)
        #expect(preferences.bottlePresetsML == nil)
    }

    @Test func resettingSettingsResetsThemInICloud() {
        let cloud = FakeCloudKeyValueStore()
        let preferences = AppPreferences(defaults: makeDefaults(), locale: Locale(identifier: "en_US"), cloud: cloud)
        preferences.bottlePresetsML = [60]
        preferences.resetToDefaults()
        #expect(cloud.values[AppPreferences.Key.bottlePresets] == nil)
    }

    // MARK: - Status

    @Test func statusFollowsSyncEvents() {
        let monitor = CloudSyncMonitor(containerID: "iCloud.test")
        #expect(monitor.status == .checking)
        var imports = 0
        monitor.onImport = { imports += 1 }

        let id = UUID()
        monitor.handle(.init(id: id, kind: .import, finished: false, succeeded: false, endDate: nil))
        #expect(monitor.status == .syncing)
        monitor.handle(.init(id: id, kind: .import, finished: true, succeeded: true, endDate: now))
        #expect(monitor.status == .upToDate(now))
        // A fetch that brought nothing new doesn't refresh the app.
        #expect(monitor.importCount == 0)
        monitor.didImportChanges()
        #expect(monitor.importCount == 1)
        #expect(imports == 1)

        // A record the server refused keeps the status at "Not synced" until it goes through.
        monitor.setSendError("Your iCloud storage is full.")
        #expect(monitor.status == .failed("Your iCloud storage is full."))
        let fetch = UUID()
        monitor.handle(.init(id: fetch, kind: .import, finished: false, succeeded: false, endDate: nil))
        monitor.handle(.init(id: fetch, kind: .import, finished: true, succeeded: true, endDate: now))
        #expect(monitor.status == .failed("Your iCloud storage is full."))
        monitor.setSendError(nil)
        #expect(monitor.status == .upToDate(now))
    }

    @Test func testsAndPreviewsDoNotSync() {
        #expect(AppConfiguration.cloudKitContainerID == nil)
        #expect(CloudSyncMonitor(containerID: nil).status == .unavailable)
        let dependencies = AppDependencies(
            clock: TestClock(), storage: .inMemory, notifications: FakeNotificationClient(), defaults: makeDefaults()
        )
        #expect(dependencies.cloudSync.status == .unavailable)
        #expect(dependencies.cloudEngine == nil)
        #expect(dependencies.cloudSharing == nil)
        #expect(dependencies.cloudSyncSwitch == nil)
    }

    // MARK: - Opt-in

    @Test func syncStartsOffOnAFreshInstallAndOnForAnExistingOne() {
        #expect(CloudSyncSwitch(defaults: makeDefaults(), isExistingInstall: false).isOn == false)
        #expect(CloudSyncSwitch(defaults: makeDefaults(), isExistingInstall: true).isOn)
    }

    /// The starting choice is saved at once: finishing onboarding later doesn't turn sync on.
    @Test func theFirstChoiceSticks() {
        let defaults = makeDefaults()
        #expect(CloudSyncSwitch(defaults: defaults, isExistingInstall: false).isOn == false)
        #expect(CloudSyncSwitch(defaults: defaults, isExistingInstall: true).isOn == false)
    }

    @Test func onboardingDoneMeansAnExistingInstall() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppPreferences.Key.onboardingComplete)
        #expect(AppDependencies.isExistingInstall(defaults: defaults))
    }

    @Test func turningSyncOnAndOffIsSaved() async throws {
        let defaults = makeDefaults()
        let syncSwitch = CloudSyncSwitch(defaults: defaults, isExistingInstall: false)
        var calls: [String] = []
        syncSwitch.activate = { calls.append("on") }
        syncSwitch.deactivate = { calls.append("off") }

        await syncSwitch.turnOn()
        #expect(syncSwitch.isOn)
        #expect(CloudSyncSwitch(defaults: defaults, isExistingInstall: false).isOn)
        try await syncSwitch.turnOff()
        #expect(syncSwitch.isOn == false)
        #expect(CloudSyncSwitch(defaults: defaults, isExistingInstall: true).isOn == false)
        #expect(calls == ["on", "off"])
    }

    /// Sharing couldn't be ended (offline): sync stays on rather than strand the partner.
    @Test func syncStaysOnWhenItCantBeTurnedOff() async {
        let syncSwitch = CloudSyncSwitch(defaults: makeDefaults(), isExistingInstall: true)
        syncSwitch.deactivate = { throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await syncSwitch.turnOff() }
        #expect(syncSwitch.isOn)
    }

    @Test func statusIsOffUntilSyncIsTurnedOn() {
        let monitor = CloudSyncMonitor(containerID: "iCloud.test", isEnabled: false)
        #expect(monitor.status == .off)
        monitor.setSendError("Your iCloud storage is full.")
        #expect(monitor.status == .off)
        monitor.setEnabled(true)
        // A send error from before sync was turned off is forgotten.
        #expect(monitor.status == .checking)
        monitor.setEnabled(false)
        #expect(monitor.status == .off)
    }

    @Test func settingsStayOnTheDeviceWhileSyncIsOff() {
        let cloud = FakeCloudKeyValueStore()
        cloud.values[AppPreferences.Key.volumeUnit] = VolumeUnit.milliliters.rawValue
        let preferences = AppPreferences(
            defaults: makeDefaults(), locale: Locale(identifier: "en_US"), cloud: cloud, cloudIsOn: false
        )
        // iCloud's settings aren't taken, and nothing is sent.
        #expect(preferences.volumeUnit == .fluidOunces)
        preferences.bottlePresetsML = [60]
        #expect(cloud.setCount == 0)
    }

    /// Turning sync on works like a new device: iCloud wins, settings only this one has go up.
    @Test func turningSyncOnMergesSettingsLikeANewDevice() {
        let cloud = FakeCloudKeyValueStore()
        cloud.values[AppPreferences.Key.volumeUnit] = VolumeUnit.milliliters.rawValue
        let preferences = AppPreferences(
            defaults: makeDefaults(), locale: Locale(identifier: "en_US"), cloud: cloud, cloudIsOn: false
        )
        preferences.pumpPresetsML = [2.0, 3.0]

        preferences.setCloudSync(true)
        #expect(preferences.volumeUnit == .milliliters)
        #expect(cloud.values[AppPreferences.Key.pumpPresets] as? [Double] == [2.0, 3.0])
        #expect(preferences.cloudChangeCount == 1)

        preferences.setCloudSync(false)
        cloud.setCount = 0
        preferences.bottlePresetsML = [90]
        #expect(cloud.setCount == 0)
    }
}

final class FakeCloudKeyValueStore: CloudKeyValueStore {
    var values: [String: Any] = [:]
    var setCount = 0

    func object(forKey key: String) -> Any? { values[key] }

    func set(_ value: Any?, forKey key: String) {
        setCount += 1
        values[key] = value
    }

    func removeObject(forKey key: String) { values[key] = nil }

    func synchronize() -> Bool { true }
}
