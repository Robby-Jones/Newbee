import Foundation

/// A bottle volume in a particular unit, as the parent sees and edits it.
public struct BottleAmount: Codable, Sendable, Hashable {
    public var value: Double
    public var unit: VolumeUnit

    public init(_ value: Double, _ unit: VolumeUnit) {
        self.value = value
        self.unit = unit
    }

    public init(milliliters: Double) {
        self.init(milliliters, .milliliters)
    }

    /// The canonical stored value.
    public var milliliters: Double { unit.toMilliliters(value) }

    /// The same volume in `target`, rounded to its display precision so a round trip
    /// (90 mL → oz → mL) doesn't drift into odd numbers.
    public func converted(to target: VolumeUnit) -> BottleAmount {
        BottleAmount(target.rounded(target == unit ? value : target.fromMilliliters(milliliters)), target)
    }

    /// One stepper tap up or down, snapped to the unit's step and clamped to `0...maximumML`.
    public func stepped(by steps: Int, maximumML: Double = BottleRules().maximumML) -> BottleAmount {
        let step = unit.step
        let snapped = (value / step).rounded() * step
        var next = snapped + Double(steps) * step
        // Snapping already moved toward the step direction: don't move twice.
        if steps > 0, snapped > value + 1e-9 { next -= step }
        if steps < 0, snapped < value - 1e-9 { next += step }
        let maximum = unit.rounded(unit.fromMilliliters(maximumML), down: true)
        return BottleAmount(min(max(0, unit.rounded(next)), maximum), unit)
    }

    /// The number only, for a text field: "90", "2.5". No unit symbol.
    public var formattedValue: String {
        VolumeUnit.format(unit.rounded(value), fractionDigits: unit == .milliliters ? 0 : 1)
    }

    /// "90 mL", "2.5 oz".
    public var formatted: String {
        "\(formattedValue) \(unit.symbol)"
    }

    /// Parses what the parent typed ("90", "2.5", "2,5"). `nil` if it isn't a number.
    public static func parse(_ text: String, unit: VolumeUnit) -> BottleAmount? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return BottleAmount(value, unit)
    }
}

extension VolumeUnit {
    /// Stepper increment: 5 mL or 0.1 oz.
    public var step: Double {
        switch self {
        case .milliliters: 5
        case .fluidOunces: 0.1
        }
    }

    /// Display precision: whole milliliters, tenths of an ounce.
    func rounded(_ value: Double, down: Bool = false) -> Double {
        let scale: Double = self == .milliliters ? 1 : 10
        let scaled = value * scale
        return (down ? (scaled + 1e-9).rounded(.down) : scaled.rounded()) / scale
    }

    static func format(_ value: Double, fractionDigits: Int) -> String {
        if fractionDigits == 0 || value == value.rounded() {
            return String(Int(value.rounded()))
        }
        return String(format: "%.\(fractionDigits)f", value)
    }
}

/// Quick-pick amounts on the Log Bottle sheet. Stored in mL (docs/DATA_MODEL.md: `bottlePresets`),
/// shown in the parent's unit. Editing them arrives with Settings.
public enum BottlePresets {
    /// Defaults for a parent who works in `unit`: 60 / 90 / 120 mL or 2 / 3 / 4 oz.
    public static func defaults(for unit: VolumeUnit) -> [BottleAmount] {
        switch unit {
        case .milliliters: [60, 90, 120].map { BottleAmount($0, .milliliters) }
        case .fluidOunces: [2, 3, 4].map { BottleAmount($0, .fluidOunces) }
        }
    }

    /// A parent keeps between 1 and 5 presets.
    public static let minimumCount = 1
    public static let maximumCount = 5

    /// Presets shown as chips on the Log Bottle sheet: the parent's own (stored in mL) or the
    /// defaults, sorted, without duplicates, and limited to amounts the rules accept.
    public static func amounts(storedML: [Double]?, unit: VolumeUnit, rules: BottleRules = BottleRules()) -> [BottleAmount] {
        guard storedML?.isEmpty == false else { return defaults(for: unit) }
        var seen = Set<Double>()
        let sorted = editable(storedML: storedML, unit: unit, rules: rules).sorted { $0.value < $1.value }
        return sorted.filter { seen.insert($0.value).inserted }
    }

    /// Presets as Settings edits them: in the order the parent made them, duplicates kept, so
    /// raising one past another never reorders or merges rows mid-edit.
    public static func editable(storedML: [Double]?, unit: VolumeUnit, rules: BottleRules = BottleRules()) -> [BottleAmount] {
        guard let storedML, !storedML.isEmpty else { return defaults(for: unit) }
        let valid = storedML
            .filter { $0 > 0 && $0 <= rules.maximumML }
            .prefix(maximumCount)
            .map { BottleAmount(milliliters: $0).converted(to: unit) }
        return valid.isEmpty ? defaults(for: unit) : Array(valid)
    }

    /// The amount a new preset starts at: one "round" step (1 oz or 30 mL) above the largest,
    /// clamped to the rules' maximum.
    public static func nextAmount(after presets: [BottleAmount], unit: VolumeUnit, rules: BottleRules = BottleRules()) -> BottleAmount {
        let largest = presets.map { $0.converted(to: unit).value }.max() ?? 0
        let increment: Double = unit == .fluidOunces ? 1 : 30
        let maximum = unit.rounded(unit.fromMilliliters(rules.maximumML), down: true)
        return BottleAmount(min(unit.rounded(largest + increment), maximum), unit)
    }
}
