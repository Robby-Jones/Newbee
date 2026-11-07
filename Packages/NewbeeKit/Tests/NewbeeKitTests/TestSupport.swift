import Foundation

/// Durations come from `Date` arithmetic, so compare them with a tolerance well below a millisecond.
func approx(_ actual: TimeInterval?, _ expected: TimeInterval, tolerance: TimeInterval = 1e-6) -> Bool {
    guard let actual else { return false }
    return abs(actual - expected) < tolerance
}
