import Foundation

/// Something a parent (or a Lock Screen button) asks the session to do.
///
/// Commands carry a *target state*, never a toggle: "switch to right", not "toggle side".
/// Replaying a command can therefore never flip the state back (docs/TIMER_ENGINE.md §3).
public enum SessionCommand: Sendable, Hashable {
    /// Begin a new session on `side`. Rejected if a session is already active or paused.
    case start(Side)
    /// Feed on `side` now. From active: closes the running segment and opens one on `side`
    /// (no-op if already on `side`). From paused: resumes on `side`.
    case switchTo(Side)
    /// Close the running segment. No-op if already paused.
    case pause
    /// Open a new segment on the last side used. No-op if already active.
    case resume
    /// Finish the session now.
    case end
    /// Finish the session at an earlier moment (recovery: "End at 2:41 AM").
    case endAt(Date)
    /// Move the running segment's start (recovery: the wall clock changed, or the parent
    /// started the timer late). Only the open segment can be adjusted.
    case adjustOpenSegmentStart(Date)
}

/// Work the caller must do after a command has been accepted, in this order:
/// persist first, then the projections.
public enum SessionEffect: Sendable, Hashable {
    /// Save the new snapshot. Always present on an accepted command.
    case persist
    /// Start or update the Live Activity to match the snapshot.
    case updateActivity
    /// End the Live Activity, showing the final snapshot.
    case endActivity
    /// Recompute reminders ("time since last feed", "still feeding?").
    case rescheduleReminders
}

/// Why the engine refused a command. None of these change state.
public enum SessionEngineError: Error, Sendable, Hashable {
    /// `start` while a session is active or paused. The UI treats this as success.
    case alreadyActive(UUID)
    /// A command that needs a session arrived when none is active or paused.
    case noActiveSession
    /// A command arrived for a session that has already ended (for example a late intent).
    case alreadyCompleted(UUID)
    /// A supplied time is before the data it must follow, or in the future.
    case invalidTime
}

/// The result of applying a command.
public struct SessionTransition: Sendable, Hashable {
    /// The session after the command. Equal to the input when `isNoOp`.
    public var snapshot: SessionSnapshot
    /// Empty for a no-op (for example a duplicate tap).
    public var effects: Set<SessionEffect>

    public init(snapshot: SessionSnapshot, effects: Set<SessionEffect>) {
        self.snapshot = snapshot
        self.effects = effects
    }

    /// `true` when the command was accepted but changed nothing (idempotent repeat).
    public var isNoOp: Bool { effects.isEmpty }
}
