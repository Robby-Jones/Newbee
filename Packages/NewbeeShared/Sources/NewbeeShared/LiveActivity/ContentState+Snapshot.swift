import Foundation
import NewbeeKit

extension FeedingActivityAttributes.ContentState {
    /// Maps the session engine's snapshot to the Live Activity payload (docs/LIVE_ACTIVITIES.md §2).
    ///
    /// - Active: the open segment is rendered by the system from `currentSegmentStart`; the
    ///   accumulated values hold closed segments only.
    /// - Paused / ended: every value is frozen. `pausedAt` holds the moment the timers stopped
    ///   (the pause, or the end of the session).
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
                revision: snapshot.revision
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
                revision: snapshot.revision
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

    /// Content becomes stale this long after the last state change. ActivityKit ends a Live
    /// Activity after 8 hours anyway; past this point views show a "check the app" hint.
    public static let staleInterval: TimeInterval = 8 * 60 * 60

    /// The `staleDate` to pass with this content.
    public var staleDate: Date {
        (currentSegmentStart ?? pausedAt ?? sessionStart).addingTimeInterval(Self.staleInterval)
    }
}
