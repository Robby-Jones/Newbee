import Foundation

/// Keeps the Live Activity in step with the session. Implemented in the app by
/// `LiveActivityCoordinator` (ActivityKit); see docs/LIVE_ACTIVITIES.md §5.
///
/// The manager calls `sync` after every saved change, in command order, never concurrently:
/// - an active or paused snapshot: start or update the activity (`lastBottle` doesn't matter);
/// - otherwise the latest finished breastfeed (or `nil`) and the latest bottle (or `nil`): keep
///   the activity and switch it to counting the time since the newer of the two ended
///   (`LatestFinishedFeed`). With neither, there are no feeds: end every activity.
///
/// It also calls it whenever bottles change (`bottlesDidChange()`), since a bottle can become,
/// or stop being, the latest feed.
@MainActor
public protocol LiveActivitySyncing: AnyObject {
    func sync(_ snapshot: SessionSnapshot?, lastBottle: BottleEntry?) async
}

extension LiveActivitySyncing {
    /// A sync with no bottles in the picture.
    public func sync(_ snapshot: SessionSnapshot?) async {
        await sync(snapshot, lastBottle: nil)
    }
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
    public func sync(_ snapshot: SessionSnapshot?, lastBottle: BottleEntry?) async {}
}

/// Used until the reminder scheduler exists, and in tests and previews.
@MainActor
public final class NoReminders: ReminderScheduling {
    public init() {}
    public func feedingDataDidChange(activeSession: SessionSnapshot?, lastCompletedSession: SessionSnapshot?) async {}
}
