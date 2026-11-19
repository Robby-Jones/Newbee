import Foundation
import NewbeeKit
import NewbeeShared
import Observation
import SwiftUI

/// Small settings kept in App Group `UserDefaults` (docs/DATA_MODEL.md, "Not in SwiftData").
/// Edited on the Settings screen; the Log Bottle sheet also remembers the last unit used.
///
/// With "Sync with iCloud" on, the `Key.synced` settings are mirrored to iCloud key-value storage
/// so every device signed in to the same Apple ID uses the same units, presets and reminders
/// (docs/ICLOUD_SYNC.md). The local defaults stay the source the app reads.
@MainActor
@Observable
final class AppPreferences {
    enum Key {
        static let volumeUnit = "volumeUnit"
        static let bottlePresets = "bottlePresets"
        static let pumpVolumeUnit = "pump.volumeUnit"
        static let pumpPresets = "pump.presets"
        static let lastBottleContents = "bottle.lastContents"
        static let reminderEnabled = "reminder.enabled"
        static let reminderIntervalMinutes = "reminder.intervalMinutes"
        static let reminderBasis = "reminder.basis"
        static let quietStart = "reminder.quietStart"
        static let quietEnd = "reminder.quietEnd"
        static let stillFeedingEnabled = "stillFeeding.enabled"
        static let stillFeedingMinutes = "stillFeeding.minutes"
        static let appearance = "appearance"
        /// Not synced and not reset: each parent picks their own theme on their own phone.
        static let colorTheme = "colorTheme"
        static let onboardingComplete = "onboardingComplete"
        static let nightShiftMorningMinute = "nightShift.morningMinute"
        static let nightShiftAlarm = "nightShift.alarm"
        static let startingSideMode = "breast.startingSide"
        static let startingSideSwitchFrom = "breast.switchFrom"

        /// Mirrored to iCloud key-value storage. Not `onboardingComplete`: each device walks
        /// through setup on its own first launch, unless it already has synced data.
        static let synced: Set<String> = [
            volumeUnit, bottlePresets, pumpVolumeUnit, pumpPresets, lastBottleContents, reminderEnabled, reminderIntervalMinutes,
            reminderBasis, quietStart, quietEnd, stillFeedingEnabled, stillFeedingMinutes, appearance,
            // Not `nightShiftAlarm`: alarms need iOS 26 and a permission, both per device.
            nightShiftMorningMinute, startingSideMode, startingSideSwitchFrom,
        ]

        /// Everything "Delete all data" resets. Appearance and `onboardingComplete` are kept
        /// (docs/DATA_MODEL.md), so deleting data doesn't throw the parent back into onboarding.
        static let resettable = [
            volumeUnit, bottlePresets, pumpVolumeUnit, pumpPresets, lastBottleContents, reminderEnabled, reminderIntervalMinutes, reminderBasis,
            quietStart, quietEnd, stillFeedingEnabled, stillFeedingMinutes, nightShiftMorningMinute, nightShiftAlarm,
            startingSideMode, startingSideSwitchFrom,
        ]
    }

    /// System, light or dark.
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }

        var title: String {
            switch self {
            case .system: String(localized: "System")
            case .light: String(localized: "Light")
            case .dark: String(localized: "Dark")
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locale: Locale
    /// iCloud key-value storage, or `nil` when this build or run never syncs.
    @ObservationIgnored private let cloudStore: (any CloudKeyValueStore)?
    /// Whether "Sync with iCloud" is on (`CloudSyncSwitch`).
    @ObservationIgnored private var cloudIsOn: Bool
    /// The key-value storage settings sync through right now, or `nil` while they stay on this
    /// device.
    private var cloud: (any CloudKeyValueStore)? { cloudIsOn ? cloudStore : nil }
    /// True while settings from iCloud are being applied, so they aren't sent straight back.
    @ObservationIgnored private var isApplyingCloudChange = false
    @ObservationIgnored private var cloudObserver: NSObjectProtocol?

    /// Goes up by one each time settings changed on another device arrive.
    private(set) var cloudChangeCount = 0

    /// The unit bottle amounts are entered and shown in everywhere (History, Insights, the PDF
    /// report…), whatever unit each bottle was logged in. Defaults to oz in US-measurement locales.
    var volumeUnit: VolumeUnit {
        didSet { store(volumeUnit.rawValue, forKey: Key.volumeUnit) }
    }

    /// The unit pumping amounts are entered and shown in, set separately from bottles. Until the
    /// parent picks one it follows the bottle unit, so nothing changes for existing users.
    var pumpVolumeUnit: VolumeUnit {
        didSet { store(pumpVolumeUnit.rawValue, forKey: Key.pumpVolumeUnit) }
    }

    /// The bottle type saved last (breast milk, formula, other), so the next bottle starts on it.
    var lastBottleContents: BottleContents? {
        didSet { store(lastBottleContents?.rawValue, forKey: Key.lastBottleContents) }
    }

    /// The parent's own bottle presets in mL, or `nil` for the defaults.
    var bottlePresetsML: [Double]? {
        didSet {
            if let bottlePresetsML {
                store(bottlePresetsML, forKey: Key.bottlePresets)
            } else {
                remove(forKey: Key.bottlePresets)
            }
        }
    }

    /// The parent's own pumping presets (per side) in mL, or `nil` for the defaults.
    var pumpPresetsML: [Double]? {
        didSet {
            if let pumpPresetsML {
                store(pumpPresetsML, forKey: Key.pumpPresets)
            } else {
                remove(forKey: Key.pumpPresets)
            }
        }
    }

    /// Feed-due reminders, quiet hours and the "Still feeding?" notice.
    var reminders: ReminderSettings {
        didSet { save(reminders) }
    }

    /// Which breast to suggest for the next feed (Settings → Breastfeeding).
    var startingSide: StartingSideSuggestion {
        didSet {
            store(startingSide.mode.rawValue, forKey: Key.startingSideMode)
            store(startingSide.switchFrom.rawValue, forKey: Key.startingSideSwitchFrom)
        }
    }

    /// When a night shift ends by itself, in minutes after midnight (docs/NIGHT_SHIFT.md).
    var nightShiftMorningMinute: Int {
        didSet { store(nightShiftMorningMinute, forKey: Key.nightShiftMorningMinute) }
    }

    /// The feed reminder rings as an alarm while this parent is on duty (iOS 26 and later).
    var nightShiftAlarm: Bool {
        didSet { store(nightShiftAlarm, forKey: Key.nightShiftAlarm) }
    }

    var appearance: Appearance {
        didSet { store(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Standard (indigo) or pink. Kept on this device only (docs/UX_SPEC.md §2.1). Setting it
    /// also makes it the theme the design tokens resolve against (`NBTheme.current`).
    var colorTheme: NBTheme {
        didSet {
            NBTheme.current = colorTheme
            store(colorTheme.rawValue, forKey: Key.colorTheme)
        }
    }

    /// Set once first-run onboarding is finished or skipped, or found unneeded because the
    /// store already has data (docs/UX_SPEC.md §3.1).
    var onboardingComplete: Bool {
        didSet { store(onboardingComplete, forKey: Key.onboardingComplete) }
    }

    init(
        defaults: UserDefaults,
        locale: Locale = .current,
        cloud: (any CloudKeyValueStore)? = nil,
        cloudIsOn: Bool = true
    ) {
        self.defaults = defaults
        self.locale = locale
        cloudStore = cloud
        self.cloudIsOn = cloudIsOn
        if let cloud = cloudIsOn ? cloud : nil {
            Self.mergeAtLaunch(defaults: defaults, cloud: cloud)
        }
        volumeUnit = Self.loadUnit(defaults, locale: locale)
        pumpVolumeUnit = Self.loadPumpUnit(defaults, locale: locale)
        bottlePresetsML = defaults.array(forKey: Key.bottlePresets) as? [Double]
        pumpPresetsML = defaults.array(forKey: Key.pumpPresets) as? [Double]
        lastBottleContents = defaults.string(forKey: Key.lastBottleContents).flatMap(BottleContents.init(rawValue:))
        reminders = Self.loadReminders(defaults)
        startingSide = Self.loadStartingSide(defaults)
        nightShiftMorningMinute = Self.loadMorningMinute(defaults)
        nightShiftAlarm = defaults.bool(forKey: Key.nightShiftAlarm)
        appearance = defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        colorTheme = defaults.string(forKey: Key.colorTheme).flatMap(NBTheme.init(rawValue:)) ?? .standard
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
        NBTheme.current = colorTheme
    }

    /// Back to first-launch values, except appearance and the color theme. Used by "Delete all data", which also
    /// resets them on the parent's other devices.
    func resetToDefaults() {
        for key in Key.resettable { remove(forKey: key) }
        volumeUnit = Self.loadUnit(defaults, locale: locale)
        pumpVolumeUnit = Self.loadPumpUnit(defaults, locale: locale)
        bottlePresetsML = nil
        pumpPresetsML = nil
        lastBottleContents = nil
        reminders = Self.loadReminders(defaults)
        startingSide = Self.loadStartingSide(defaults)
        nightShiftMorningMinute = Self.loadMorningMinute(defaults)
        nightShiftAlarm = false
    }

    private static func loadStartingSide(_ defaults: UserDefaults) -> StartingSideSuggestion {
        let fallback = StartingSideSuggestion()
        return StartingSideSuggestion(
            mode: defaults.string(forKey: Key.startingSideMode).flatMap(StartingSideSuggestion.Mode.init(rawValue:)) ?? fallback.mode,
            switchFrom: defaults.string(forKey: Key.startingSideSwitchFrom).flatMap(StartingSideSuggestion.SwitchFrom.init(rawValue:))
                ?? fallback.switchFrom
        )
    }

    private static func loadMorningMinute(_ defaults: UserDefaults) -> Int {
        defaults.object(forKey: Key.nightShiftMorningMinute) as? Int ?? NightShiftSchedule.defaultMorningMinute
    }

    private static func loadUnit(_ defaults: UserDefaults, locale: Locale) -> VolumeUnit {
        defaults.string(forKey: Key.volumeUnit).flatMap(VolumeUnit.init(rawValue:))
            ?? (locale.measurementSystem == .us ? .fluidOunces : .milliliters)
    }

    private static func loadPumpUnit(_ defaults: UserDefaults, locale: Locale) -> VolumeUnit {
        defaults.string(forKey: Key.pumpVolumeUnit).flatMap(VolumeUnit.init(rawValue:))
            ?? loadUnit(defaults, locale: locale)
    }

    private static func loadReminders(_ defaults: UserDefaults) -> ReminderSettings {
        let fallback = ReminderSettings()
        var settings = fallback
        settings.isEnabled = defaults.bool(forKey: Key.reminderEnabled)
        if let minutes = defaults.object(forKey: Key.reminderIntervalMinutes) as? Int, minutes > 0 {
            settings.interval = TimeInterval(minutes * 60)
        }
        settings.basis = defaults.string(forKey: Key.reminderBasis).flatMap(ReminderSettings.Basis.init(rawValue:)) ?? fallback.basis
        if let start = defaults.object(forKey: Key.quietStart) as? Int, let end = defaults.object(forKey: Key.quietEnd) as? Int {
            settings.quietHours = QuietHours(startMinute: start, endMinute: end)
        }
        if let enabled = defaults.object(forKey: Key.stillFeedingEnabled) as? Bool {
            settings.stillFeedingEnabled = enabled
        }
        if let minutes = defaults.object(forKey: Key.stillFeedingMinutes) as? Int, minutes > 0 {
            settings.stillFeedingThreshold = TimeInterval(minutes * 60)
        }
        return settings
    }

    private func save(_ settings: ReminderSettings) {
        store(settings.isEnabled, forKey: Key.reminderEnabled)
        store(Int(settings.interval / 60), forKey: Key.reminderIntervalMinutes)
        store(settings.basis.rawValue, forKey: Key.reminderBasis)
        if let quiet = settings.quietHours {
            store(quiet.startMinute, forKey: Key.quietStart)
            store(quiet.endMinute, forKey: Key.quietEnd)
        } else {
            remove(forKey: Key.quietStart)
            remove(forKey: Key.quietEnd)
        }
        store(settings.stillFeedingEnabled, forKey: Key.stillFeedingEnabled)
        store(Int(settings.stillFeedingThreshold / 60), forKey: Key.stillFeedingMinutes)
    }

    // MARK: - Storage and iCloud

    /// Writes a value locally and, for a synced key, to iCloud. `nil` removes it.
    private func store(_ value: Any?, forKey key: String) {
        guard let value else {
            remove(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
        if let cloud, !isApplyingCloudChange, Key.synced.contains(key) {
            cloud.set(value, forKey: key)
        }
    }

    private func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
        if let cloud, !isApplyingCloudChange, Key.synced.contains(key) {
            cloud.removeObject(forKey: key)
        }
    }

    /// At launch iCloud wins for settings it has, so a new device picks up the parent's
    /// settings. Settings only this device has are sent up, so a first sync loses nothing.
    private static func mergeAtLaunch(defaults: UserDefaults, cloud: any CloudKeyValueStore) {
        for key in Key.synced {
            if let value = cloud.object(forKey: key) {
                defaults.set(value, forKey: key)
            } else if let value = defaults.object(forKey: key) {
                cloud.set(value, forKey: key)
            }
        }
    }

    /// "Sync with iCloud" was turned on or off. Turning it on works like launching on a new
    /// device: settings already in iCloud replace this device's, and settings only this device
    /// has are sent up. Turning it off keeps the current settings on this device.
    func setCloudSync(_ isOn: Bool) {
        guard isOn != cloudIsOn else { return }
        cloudIsOn = isOn
        if isOn, let cloud {
            _ = cloud.synchronize()
            Self.mergeAtLaunch(defaults: defaults, cloud: cloud)
            reloadFromDefaults()
            cloudChangeCount += 1
            startCloudSync()
        } else if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
            self.cloudObserver = nil
        }
    }

    /// Starts listening for settings changed on other devices. Call at launch while sync is on.
    func startCloudSync() {
        guard let cloud, cloudObserver == nil else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main
        ) { notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            // Preferences live as long as the app (`AppDependencies.shared`).
            Task { @MainActor in self.applyCloudChange(keys: keys, reason: reason) }
        }
        _ = cloud.synchronize()
    }

    /// Applies settings that changed in iCloud. Internal for tests.
    func applyCloudChange(keys: [String]?, reason: Int?) {
        guard let cloud else { return }
        if reason == NSUbiquitousKeyValueStoreAccountChange {
            // A different Apple ID: its settings, if it has any, replace this one's.
            Self.mergeAtLaunch(defaults: defaults, cloud: cloud)
        } else {
            for key in (keys ?? Array(Key.synced)) where Key.synced.contains(key) {
                if let value = cloud.object(forKey: key) {
                    defaults.set(value, forKey: key)
                } else if reason != NSUbiquitousKeyValueStoreInitialSyncChange {
                    // Removed on another device, e.g. by "Delete all data".
                    defaults.removeObject(forKey: key)
                }
            }
        }
        reloadFromDefaults()
        cloudChangeCount += 1
    }

    /// Re-reads every setting from the local defaults without sending anything to iCloud.
    private func reloadFromDefaults() {
        isApplyingCloudChange = true
        defer { isApplyingCloudChange = false }
        volumeUnit = Self.loadUnit(defaults, locale: locale)
        pumpVolumeUnit = Self.loadPumpUnit(defaults, locale: locale)
        bottlePresetsML = defaults.array(forKey: Key.bottlePresets) as? [Double]
        pumpPresetsML = defaults.array(forKey: Key.pumpPresets) as? [Double]
        lastBottleContents = defaults.string(forKey: Key.lastBottleContents).flatMap(BottleContents.init(rawValue:))
        reminders = Self.loadReminders(defaults)
        startingSide = Self.loadStartingSide(defaults)
        nightShiftMorningMinute = Self.loadMorningMinute(defaults)
        appearance = defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    /// The App Group defaults, or a throwaway domain under UI tests so runs don't leak into each other.
    static func makeDefaults() -> UserDefaults {
        if AppConfiguration.isUITesting {
            let name = "NewbeeUITests"
            let defaults = UserDefaults(suiteName: name) ?? .standard
            defaults.removePersistentDomain(forName: name)
            // `-uiTestColorTheme pink`: start in that theme (review screenshots).
            if let theme = UserDefaults.standard.string(forKey: "uiTestColorTheme") {
                defaults.set(theme, forKey: Key.colorTheme)
            }
            return defaults
        }
        return UserDefaults(suiteName: AppConfiguration.appGroupID) ?? .standard
    }
}

/// The parts of `NSUbiquitousKeyValueStore` the app uses, so tests can use a fake.
protocol CloudKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {}
