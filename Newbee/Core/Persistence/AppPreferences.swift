import Foundation
import NewbeeKit
import Observation
import SwiftUI

/// Small settings kept in App Group `UserDefaults` (docs/DATA_MODEL.md, "Not in SwiftData").
/// Edited on the Settings screen; the Log Bottle sheet also remembers the last unit used.
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
        static let onboardingComplete = "onboardingComplete"

        /// Everything "Delete all data" resets. Appearance and `onboardingComplete` are kept
        /// (docs/DATA_MODEL.md), so deleting data doesn't throw the parent back into onboarding.
        static let resettable = [
            volumeUnit, bottlePresets, pumpVolumeUnit, pumpPresets, lastBottleContents, reminderEnabled, reminderIntervalMinutes, reminderBasis,
            quietStart, quietEnd, stillFeedingEnabled, stillFeedingMinutes,
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

    /// The unit bottle amounts are entered and shown in everywhere (History, Insights, the PDF
    /// report…), whatever unit each bottle was logged in. Defaults to oz in US-measurement locales.
    var volumeUnit: VolumeUnit {
        didSet { defaults.set(volumeUnit.rawValue, forKey: Key.volumeUnit) }
    }

    /// The unit pumping amounts are entered and shown in, set separately from bottles. Until the
    /// parent picks one it follows the bottle unit, so nothing changes for existing users.
    var pumpVolumeUnit: VolumeUnit {
        didSet { defaults.set(pumpVolumeUnit.rawValue, forKey: Key.pumpVolumeUnit) }
    }

    /// The bottle type saved last (breast milk, formula, other), so the next bottle starts on it.
    var lastBottleContents: BottleContents? {
        didSet { defaults.set(lastBottleContents?.rawValue, forKey: Key.lastBottleContents) }
    }

    /// The parent's own bottle presets in mL, or `nil` for the defaults.
    var bottlePresetsML: [Double]? {
        didSet {
            if let bottlePresetsML {
                defaults.set(bottlePresetsML, forKey: Key.bottlePresets)
            } else {
                defaults.removeObject(forKey: Key.bottlePresets)
            }
        }
    }

    /// The parent's own pumping presets (per side) in mL, or `nil` for the defaults.
    var pumpPresetsML: [Double]? {
        didSet {
            if let pumpPresetsML {
                defaults.set(pumpPresetsML, forKey: Key.pumpPresets)
            } else {
                defaults.removeObject(forKey: Key.pumpPresets)
            }
        }
    }

    /// Feed-due reminders, quiet hours and the "Still feeding?" notice.
    var reminders: ReminderSettings {
        didSet { save(reminders) }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Set once first-run onboarding is finished or skipped, or found unneeded because the
    /// store already has data (docs/UX_SPEC.md §3.1).
    var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Key.onboardingComplete) }
    }

    init(defaults: UserDefaults, locale: Locale = .current) {
        self.defaults = defaults
        self.locale = locale
        volumeUnit = Self.loadUnit(defaults, locale: locale)
        pumpVolumeUnit = Self.loadPumpUnit(defaults, locale: locale)
        bottlePresetsML = defaults.array(forKey: Key.bottlePresets) as? [Double]
        pumpPresetsML = defaults.array(forKey: Key.pumpPresets) as? [Double]
        lastBottleContents = defaults.string(forKey: Key.lastBottleContents).flatMap(BottleContents.init(rawValue:))
        reminders = Self.loadReminders(defaults)
        appearance = defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
    }

    /// Back to first-launch values, except appearance. Used by "Delete all data".
    func resetToDefaults() {
        for key in Key.resettable { defaults.removeObject(forKey: key) }
        volumeUnit = Self.loadUnit(defaults, locale: locale)
        pumpVolumeUnit = Self.loadPumpUnit(defaults, locale: locale)
        bottlePresetsML = nil
        pumpPresetsML = nil
        lastBottleContents = nil
        reminders = Self.loadReminders(defaults)
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
        defaults.set(settings.isEnabled, forKey: Key.reminderEnabled)
        defaults.set(Int(settings.interval / 60), forKey: Key.reminderIntervalMinutes)
        defaults.set(settings.basis.rawValue, forKey: Key.reminderBasis)
        if let quiet = settings.quietHours {
            defaults.set(quiet.startMinute, forKey: Key.quietStart)
            defaults.set(quiet.endMinute, forKey: Key.quietEnd)
        } else {
            defaults.removeObject(forKey: Key.quietStart)
            defaults.removeObject(forKey: Key.quietEnd)
        }
        defaults.set(settings.stillFeedingEnabled, forKey: Key.stillFeedingEnabled)
        defaults.set(Int(settings.stillFeedingThreshold / 60), forKey: Key.stillFeedingMinutes)
    }

    /// The App Group defaults, or a throwaway domain under UI tests so runs don't leak into each other.
    static func makeDefaults() -> UserDefaults {
        if AppConfiguration.isUITesting {
            let name = "NewbeeUITests"
            let defaults = UserDefaults(suiteName: name) ?? .standard
            defaults.removePersistentDomain(forName: name)
            return defaults
        }
        return UserDefaults(suiteName: AppConfiguration.appGroupID) ?? .standard
    }
}
