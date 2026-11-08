import Foundation

/// A breast side. Raw values are persisted; never rename them.
public enum Side: String, Codable, Sendable, CaseIterable, Hashable {
    case left
    case right

    public var opposite: Side { self == .left ? .right : .left }

    /// Single-letter label shown next to side colors (color is never the only signal).
    public var shortLabel: String { self == .left ? "L" : "R" }
}

/// Lifecycle of a feeding session. "Not started" is represented by the absence of a session.
public enum SessionStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case active
    case paused
    case completed
}

/// The kind of session recorded. `pump` is a pumping session (not a feed); `combo` is reserved.
public enum FeedingKind: String, Codable, Sendable, CaseIterable, Hashable {
    case breast
    case bottle
    case pump
    case combo
}

/// What a bottle contained.
public enum BottleContents: String, Codable, Sendable, CaseIterable, Hashable {
    case breastMilk
    case formula
    case other
}

/// How a session's data was captured. Insights use this to flag estimated values.
public enum EntrySource: String, Codable, Sendable, CaseIterable, Hashable {
    /// Recorded live with the timer.
    case timer
    /// Entered or reconstructed by hand.
    case manual
    /// Closed by the recovery flow with an estimated end time.
    case recovered
}
