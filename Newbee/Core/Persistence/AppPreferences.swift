import Foundation
import NewbeeKit
import Observation

/// Small settings kept in App Group `UserDefaults` (docs/DATA_MODEL.md, "Not in SwiftData").
/// The Settings screen edits these later; for now the Log Bottle sheet remembers the unit.
@MainActor
@Observable
final class AppPreferences {
    enum Key {
        static let volumeUnit = "volumeUnit"
        static let bottlePresets = "bottlePresets"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The unit bottle amounts are entered and shown in. Defaults to oz in US-measurement locales.
    var volumeUnit: VolumeUnit {
        didSet { defaults.set(volumeUnit.rawValue, forKey: Key.volumeUnit) }
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

    init(defaults: UserDefaults, locale: Locale = .current) {
        self.defaults = defaults
        volumeUnit = defaults.string(forKey: Key.volumeUnit).flatMap(VolumeUnit.init(rawValue:))
            ?? (locale.measurementSystem == .us ? .fluidOunces : .milliliters)
        bottlePresetsML = defaults.array(forKey: Key.bottlePresets) as? [Double]
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
