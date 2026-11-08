import Foundation

/// Keeps the Live Activity in step with the session. Implemented in the app by
/// `LiveActivityCoordinator` (ActivityKit); see docs/LIVE_ACTIVITIES.md §5.
///
/// The manager calls `sync` after every saved change, in command order, never concurrently:
/// - an active or paused snapshot: start or update the activity;
/// - a completed snapshot (the latest finished feed, when none is running): keep the activity
///   and switch it to counting the time since that feed ended;
/// - `nil`: no feeds at all: end every activity.
@MainActor
public protocol LiveActivitySyncing: AnyObject {
    func sync(_ snapshot: SessionSnapshot?) async
}

/// Recomputes local notifications ("time since last feed", "still feeding?") whenever feeding
/// data changes. Implemented in the app by `ReminderScheduler` (Phase 5b).
@MainActor
public protocol ReminderScheduling: AnyObject {
    func feedingDataDidChange(activeSession: SessionSnapshot?, lastCompletedSession: SessionSnapshot?) async
}

/// Used until the Live Activity coordinator is wired in, and in tests and previews.
@MainActor
public final class NoLiveActivities: LiveActivitySyncing {
    public init() {}
    public func sync(_ snapshot: SessionSnapshot?) async {}
}

/// Used until the reminder scheduler exists, and in tests and previews.
@MainActor
public final class NoReminders: ReminderScheduling {
    public init() {}
    public func feedingDataDidChange(activeSession: SessionSnapshot?, lastCompletedSession: SessionSnapshot?) async {}
}
