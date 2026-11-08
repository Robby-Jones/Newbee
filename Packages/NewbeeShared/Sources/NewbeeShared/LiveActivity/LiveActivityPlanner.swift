import Foundation
import NewbeeKit

/// What the coordinator knows about one Live Activity the system is holding for us.
public struct LiveActivityRecord: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        /// Requested, showing, or stale: it can still be updated or ended.
        case live
        /// Ended but still on the Lock Screen (the system ended it at the 8-hour limit, or an older
        /// build's "Feed complete" summary). Can't be updated, but an immediate end removes it.
        case ended
        /// Gone from the Lock Screen. Nothing to do with it.
        case dismissed
    }

    public var id: String
    /// The session the activity currently shows: `state.sessionID`, falling back to the
    /// attributes for content from older builds. See `sessionID(attributes:state:)`.
    public var sessionID: UUID
    /// The session the activity was requested for (`FeedingActivityAttributes.sessionID`). Differs
    /// from `sessionID` when the activity was carried over to another feed, so it is still on the
    /// older feed's 8-hour clock.
    public var requestedForSessionID: UUID
    public var state: FeedingActivityAttributes.ContentState
    public var phase: Phase

    public init(
        id: String,
        sessionID: UUID,
        requestedForSessionID: UUID? = nil,
        state: FeedingActivityAttributes.ContentState,
        phase: Phase
    ) {
        self.id = id
        self.sessionID = sessionID
        self.requestedForSessionID = requestedForSessionID ?? sessionID
        self.state = state
        self.phase = phase
    }

    /// Showing a different feed from the one it was requested for (see `requestedForSessionID`).
    public var isCarriedOver: Bool { requestedForSessionID != sessionID }

    /// The session an activity shows: its content's session, or the one it was requested for.
    public static func sessionID(
        attributes: FeedingActivityAttributes,
        state: FeedingActivityAttributes.ContentState
    ) -> UUID {
        state.sessionID ?? attributes.sessionID
    }
}

/// When an ended activity leaves the Lock Screen.
public enum LiveActivityDismissal: Hashable, Sendable {
    case immediate
    case after(Date)
}

/// One ActivityKit call for the coordinator to make.
public enum LiveActivityAction: Hashable, Sendable {
    /// Request a new activity. If `replacing` names a running activity, the coordinator ends it
    /// once the request succeeds, or, if the system refuses the request (the app is in the
    /// background, e.g. a feed started from the Lock Screen), updates it to `state` instead, so
    /// the parent never loses the activity.
    case request(FeedingActivityAttributes, FeedingActivityAttributes.ContentState, staleDate: Date, replacing: String? = nil)
    case update(id: String, FeedingActivityAttributes.ContentState, staleDate: Date)
    case end(id: String, finalState: FeedingActivityAttributes.ContentState?, dismissal: LiveActivityDismissal)
}

/// Decides how to make the system's Live Activities match a session snapshot
/// (docs/LIVE_ACTIVITIES.md §5–6). Pure, so every reconciliation case is unit tested; the
/// app's `LiveActivityCoordinator` only executes the returned actions.
///
/// Order of truth is SwiftData → snapshot → Live Activity, never the reverse.
///
/// One activity covers a feed and the gap after it: while the feed runs it shows the timers, and
/// once it ends the same activity counts up the time since that feed ended. The next feed gets a
/// freshly requested activity, which restarts ActivityKit's 8-hour clock. When iOS refuses that
/// request (the app is in the background), the old activity is carried over to the new feed, and
/// replaced with a fresh one at the next sync that can request (any sync in the foreground).
public struct LiveActivityPlanner: Sendable {
    /// After this long without a change, the content goes stale and the views show
    /// "Still feeding? Open Newbee". Should equal the engine's `RecoveryPolicy` threshold so the
    /// Lock Screen nudges exactly when the app would ask.
    public var staleAfter: TimeInterval

    public init(staleAfter: TimeInterval = 45 * 60) {
        self.staleAfter = staleAfter
    }

    /// - Parameters:
    ///   - snapshot: The active session; when no feed is running, the most recent completed
    ///     session (shown as time since it ended); `nil` when there is neither.
    ///   - existing: Every activity of ours the system currently reports.
    ///   - activitiesEnabled: `ActivityAuthorizationInfo().areActivitiesEnabled`.
    ///   - dismissedAtRevision: If the parent swiped this session's activity away, the revision it
    ///     showed then. We don't bring it back until the session changes again.
    ///   - babyName: Shown in the activity's header; `""` for a generic title.
    ///   - now: Current time.
    public func plan(
        for snapshot: SessionSnapshot?,
        existing: [LiveActivityRecord],
        activitiesEnabled: Bool,
        dismissedAtRevision: Int? = nil,
        babyName: String = "",
        now: Date
    ) -> [LiveActivityAction] {
        let live = existing.filter { $0.phase == .live }
        let ended = existing.filter { $0.phase == .ended }

        guard let snapshot else {
            // No feed at all (e.g. the only one was deleted): nothing to show.
            return live.map(Self.removeNow)
        }

        let state = FeedingActivityAttributes.ContentState(snapshot: snapshot)
        let staleDate = state.staleDate(after: staleAfter)
        let mine = live.filter { $0.sessionID == snapshot.id }

        if snapshot.status == .completed {
            return planSinceLastFeed(snapshot: snapshot, state: state, staleDate: staleDate, live: live, ended: ended)
        }

        // Active or paused. Anything left in the ended state (the 8-hour limit, or an older
        // build's summary) is now wrong.
        var actions = ended.map(Self.removeNow)

        // Keep exactly one live activity for this session.
        guard let keep = Self.newest(mine) else {
            // A new feed, or its activity was lost. Running activities for other sessions are
            // the previous feed's since-last-feed count (or leftovers): the one the parent is
            // most likely looking at is replaced by the new request, the rest go now.
            let previous = Self.mostRecentFeed(live)
            actions += live.filter { $0.id != previous?.id }.map(Self.removeNow)
            let userDismissedThisState = dismissedAtRevision.map { snapshot.revision <= $0 } ?? false
            if activitiesEnabled && !userDismissedThisState {
                let attributes = FeedingActivityAttributes(sessionID: snapshot.id, babyName: babyName)
                actions.append(.request(attributes, state, staleDate: staleDate, replacing: previous?.id))
            } else if let previous {
                actions.append(Self.removeNow(previous))
            }
            return actions
        }

        actions += live.filter { $0.id != keep.id }.map(Self.removeNow)
        if keep.isCarriedOver && activitiesEnabled {
            // Still on an older feed's 8-hour clock: swap in a fresh activity when iOS allows it
            // (if it refuses, the coordinator updates this one instead, as when it was carried).
            let attributes = FeedingActivityAttributes(sessionID: snapshot.id, babyName: babyName)
            actions.append(.request(attributes, state, staleDate: staleDate, replacing: keep.id))
            return actions
        }
        actions += Self.update(keep, to: state, staleDate: staleDate, sameSession: true)
        return actions
    }

    /// No feed is running: the activity that showed the feed (or, if that feed was deleted, any
    /// activity still running) switches to the time since `snapshot` ended. Never requests one:
    /// opening the app shouldn't put an activity back that the parent swiped away or that
    /// reached the time limit; the next feed brings it back.
    private func planSinceLastFeed(
        snapshot: SessionSnapshot,
        state: FeedingActivityAttributes.ContentState,
        staleDate: Date,
        live: [LiveActivityRecord],
        ended: [LiveActivityRecord]
    ) -> [LiveActivityAction] {
        let mine = live.filter { $0.sessionID == snapshot.id }
        guard let keep = Self.newest(mine) ?? Self.mostRecentFeed(live) else {
            // Nothing running. An ended activity (the 8-hour limit) may still be on the Lock
            // Screen. It can't be updated, so one already counting from this feed's end is left
            // to time out; any other is showing the wrong thing and goes now.
            return ended
                .filter { $0.sessionID != snapshot.id || $0.state.lastFeedEndedAt != state.lastFeedEndedAt }
                .map(Self.removeNow)
        }
        var actions = ended.map(Self.removeNow)
        actions += live.filter { $0.id != keep.id }.map(Self.removeNow)
        actions += Self.update(keep, to: state, staleDate: staleDate, sameSession: keep.sessionID == snapshot.id)
        return actions
    }

    private static func update(
        _ record: LiveActivityRecord,
        to state: FeedingActivityAttributes.ContentState,
        staleDate: Date,
        sameSession: Bool
    ) -> [LiveActivityAction] {
        guard record.state != state else { return [] }
        // Never move an activity backwards to an older revision of the same session.
        if sameSession && record.state.revision > state.revision { return [] }
        return [.update(id: record.id, state, staleDate: staleDate)]
    }

    /// Among records of one session: the highest revision.
    private static func newest(_ records: [LiveActivityRecord]) -> LiveActivityRecord? {
        records.max(by: { $0.state.revision < $1.state.revision })
    }

    /// Among records of different sessions, whose revisions can't be compared: a since-last-feed
    /// count first (the latest feed end), else the feed that started last.
    private static func mostRecentFeed(_ records: [LiveActivityRecord]) -> LiveActivityRecord? {
        let counting = records.filter { $0.state.lastFeedEndedAt != nil }
        if let latest = counting.max(by: { $0.state.lastFeedEndedAt! < $1.state.lastFeedEndedAt! }) {
            return latest
        }
        return records.max(by: { $0.state.sessionStart < $1.state.sessionStart })
    }

    private static func removeNow(_ record: LiveActivityRecord) -> LiveActivityAction {
        .end(id: record.id, finalState: nil, dismissal: .immediate)
    }
}
