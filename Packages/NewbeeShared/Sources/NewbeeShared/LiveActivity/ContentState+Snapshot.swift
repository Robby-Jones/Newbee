import Foundation
import NewbeeKit

extension FeedingActivityAttributes.ContentState {
    /// Maps the session engine's snapshot to the Live Activity payload (docs/LIVE_ACTIVITIES.md §2).
    ///
    /// - Active: the open segment is rendered by the system from `currentSegmentStart`; the
    ///   accumulated values hold closed segments only.
    /// - Paused: every value is frozen. `pausedAt` holds the moment the timers stopped.
    /// - Completed (`.ended`): the side times are frozen at the end of the feed, and `pausedAt`
    ///   holds that end, which the views count up from to show the time since the last feed.
    ///
    /// The mapping is defensive about inconsistent snapshots: an "active" snapshot without an open
    /// segment is shown as paused rather than ticking from a wrong start.
    public init(snapshot: SessionSnapshot) {
        let side = snapshot.lastSide ?? .left
        let open = snapshot.openSegment

        switch snapshot.status {
        case .active where open != nil:
            self.init(
                status: .active,
                currentSide: open?.side ?? side,
                sessionStart: snapshot.startedAt,
                currentSegmentStart: open?.start,
                leftAccumulated: snapshot.closedDuration(on: .left),
                rightAccumulated: snapshot.closedDuration(on: .right),
                pausedAt: nil,
                revision: snapshot.revision,
                sessionID: snapshot.id
            )
        case .active, .paused, .completed:
            let frozenAt = Self.freezeTime(of: snapshot)
            self.init(
                status: snapshot.status == .completed ? .ended : .paused,
                currentSide: side,
                sessionStart: snapshot.startedAt,
                currentSegmentStart: nil,
                leftAccumulated: snapshot.duration(on: .left, at: frozenAt),
                rightAccumulated: snapshot.duration(on: .right, at: frozenAt),
                pausedAt: frozenAt,
                revision: snapshot.revision,
                sessionID: snapshot.id
            )
        }
    }

    /// When the timers stopped for a paused or completed snapshot.
    private static func freezeTime(of snapshot: SessionSnapshot) -> Date {
        if snapshot.status == .completed, let ended = snapshot.endedAt { return ended }
        let lastClosedEnd = snapshot.segments.compactMap(\.end).max()
        return lastClosedEnd ?? snapshot.endedAt ?? snapshot.startedAt
    }

    /// Accumulated time on both sides from closed segments.
    public var totalAccumulated: TimeInterval { leftAccumulated + rightAccumulated }

    /// Time on `side` as of `now`, including the running segment. Used for accessibility labels
    /// and tests; views render running values with system timers instead.
    public func duration(on side: Side, at now: Date) -> TimeInterval {
        var value = accumulated(on: side)
        if status == .active, side == currentSide, let start = currentSegmentStart {
            value += max(0, now.timeIntervalSince(start))
        }
        return value
    }

    /// Total feeding time as of `now` (pauses excluded).
    public func total(at now: Date) -> TimeInterval {
        duration(on: .left, at: now) + duration(on: .right, at: now)
    }

    /// Whether `side` is the running side.
    public func isRunning(_ side: Side) -> Bool {
        status == .active && currentSide == side
    }

    /// The `staleDate` to pass with this content: `threshold` after the running segment started
    /// (or after the pause). Pass the same "still feeding?" threshold the in-app recovery prompt
    /// uses, so the Lock Screen shows "Still feeding? Open Newbee" exactly when the app would ask.
    ///
    /// The since-last-feed count is never out of date, so its stale date is used for something
    /// else: it is the one-hour mark (`sinceLastFeedHourMark`), where the system redraws the
    /// activity so the count can switch from "00:59" to "01:00" (see `SinceLastFeedFormat`).
    public func staleDate(after threshold: TimeInterval) -> Date {
        if let sinceLastFeedHourMark { return sinceLastFeedHourMark }
        return (currentSegmentStart ?? pausedAt ?? sessionStart).addingTimeInterval(threshold)
    }

    /// One hour after the last feed ended, while no feed is running.
    public var sinceLastFeedHourMark: Date? {
        lastFeedEndedAt?.addingTimeInterval(3600)
    }
}
