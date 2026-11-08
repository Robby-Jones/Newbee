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
/// It also calls it whenever bottles change (`bottlesDidChange(logged:)`), since a bottle can
/// become, or stop being, the latest feed.
///
/// `mode` says how far the sync may go to put an activity on screen (`LiveActivitySyncMode`).
@MainActor
public protocol LiveActivitySyncing: AnyObject {
    func sync(_ snapshot: SessionSnapshot?, lastBottle: BottleEntry?, mode: LiveActivitySyncMode) async
}

/// How far a Live Activity sync may go to put an activity on screen.
public enum LiveActivitySyncMode: Sendable, Hashable {
    /// Bring what's showing up to date. A running feed gets an activity if it has none (a new
    /// feed, or one lost to a reboot), unless the parent swiped this state away. The
    /// since-last-feed count is never started on its own, so opening the app doesn't put back an
    /// activity the parent dismissed.
    case update
    /// The parent just entered a feed (a bottle, or a breastfeed added by hand) and it is now the
    /// latest one: also start an activity for the count if none is showing, even after a swipe.
    case show
    /// Settings' "Refresh Live Activity": replace whatever is showing with a freshly requested
    /// activity for the current state (which also restarts ActivityKit's 8-hour clock).
    case refresh
}

extension LiveActivitySyncing {
    public func sync(_ snapshot: SessionSnapshot?, lastBottle: BottleEntry?) async {
        await sync(snapshot, lastBottle: lastBottle, mode: .update)
    }

    /// A sync with no bottles in the picture.
    public func sync(_ snapshot: SessionSnapshot?) async {
        await sync(snapshot, lastBottle: nil, mode: .update)
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
    public func sync(_ snapshot: SessionSnapshot?, lastBottle: BottleEntry?, mode: LiveActivitySyncMode) async {}
}

/// Used until the reminder scheduler exists, and in tests and previews.
@MainActor
public final class NoReminders: ReminderScheduling {
    public init() {}
    public func feedingDataDidChange(activeSession: SessionSnapshot?, lastCompletedSession: SessionSnapshot?) async {}
}
