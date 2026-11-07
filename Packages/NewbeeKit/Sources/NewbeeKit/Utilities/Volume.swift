import Foundation

/// Units a parent can enter bottle volumes in. Volumes are always stored in millilitres.
public enum VolumeUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case milliliters = "ml"
    case fluidOunces = "oz"

    /// Millilitres in one US fluid ounce.
    public static let millilitersPerFluidOunce = 29.5735295625

    public func toMilliliters(_ value: Double) -> Double {
        switch self {
        case .milliliters: value
        case .fluidOunces: value * Self.millilitersPerFluidOunce
        }
    }

    public func fromMilliliters(_ ml: Double) -> Double {
        switch self {
        case .milliliters: ml
        case .fluidOunces: ml / Self.millilitersPerFluidOunce
        }
    }

    public var symbol: String {
        switch self {
        case .milliliters: "mL"
        case .fluidOunces: "oz"
        }
    }
}
