import Foundation
import Observation

/// Settings → iCloud → "Sync with iCloud" (docs/ICLOUD_SYNC.md).
///
/// iCloud sync is opt-in: a fresh install keeps everything on the phone until the parent turns it
/// on. Installs from before the switch existed synced on their own, so they keep syncing. The
/// choice is this device's own: it isn't synced, and "Delete all data" keeps it.
///
/// The switch only records the choice and says when it changes. `AppDependencies` does the work
/// (`CloudSyncWiring`).
@MainActor
@Observable
final class CloudSyncSwitch {
    static let key = "iCloudSyncEnabled"

    private(set) var isOn: Bool
    /// True while sync is being turned on or off.
    private(set) var isWorking = false

    /// Starts syncing: settings, then feeds, then a full fetch from iCloud.
    @ObservationIgnored var activate: (@MainActor () async -> Void)?
    /// Stops syncing. Ends sharing first, which needs iCloud: throws without changing anything if
    /// that fails.
    @ObservationIgnored var deactivate: (@MainActor () async throws -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameter isExistingInstall: The app ran before on this device, back when sync was always
    ///   on. Only read the first time, when no choice is saved yet.
    init(defaults: UserDefaults, isExistingInstall: Bool) {
        self.defaults = defaults
        isOn = Self.resolve(defaults: defaults, isExistingInstall: isExistingInstall)
    }

    /// The saved choice, or the starting one: on for an install that synced before the switch
    /// existed, off for a new one. The starting choice is saved at once, so it never changes later
    /// (finishing onboarding doesn't turn sync on).
    static func resolve(defaults: UserDefaults, isExistingInstall: Bool) -> Bool {
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        defaults.set(isExistingInstall, forKey: key)
        return isExistingInstall
    }

    func turnOn() async {
        guard !isOn, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        isOn = true
        defaults.set(true, forKey: Self.key)
        await activate?()
    }

    func turnOff() async throws {
        guard isOn, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        try await deactivate?()
        isOn = false
        defaults.set(false, forKey: Self.key)
    }
}
