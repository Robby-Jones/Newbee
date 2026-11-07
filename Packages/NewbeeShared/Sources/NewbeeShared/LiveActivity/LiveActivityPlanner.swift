import Foundation
import NewbeeKit

/// What the coordinator knows about one Live Activity the system is holding for us.
public struct LiveActivityRecord: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        /// Requested, showing, or stale: it can still be updated or ended.
        case live
        /// Ended but still on the Lock Screen (the 15-minute summary, or the system ended it at
        /// the 8-hour limit). Can't be updated, but an immediate end removes it.
        case ended
        /// Gone from the Lock Screen. Nothing to do with it.
        case dismissed
    }

    public var id: String
    public var sessionID: UUID
    public var state: FeedingActivityAttributes.ContentState
    public var phase: Phase

    public init(id: String, sessionID: UUID, state: FeedingActivityAttributes.ContentState, phase: Phase) {
        self.id = id
        self.sessionID = sessionID
        self.state = state
        self.phase = phase
    }
}

/// When an ended activity leaves the Lock Screen.
public enum LiveActivityDismissal: Hashable, Sendable {
    case immediate
    case after(Date)
}

/// One ActivityKit call for the coordinator to make.
public enum LiveActivityAction: Hashable, Sendable {
    case request(FeedingActivityAttributes, FeedingActivityAttributes.ContentState, staleDate: Date)
    case update(id: String, FeedingActivityAttributes.ContentState, staleDate: Date)
    case end(id: String, finalState: FeedingActivityAttributes.ContentState?, dismissal: LiveActivityDismissal)
}

/// Decides how to make the system's Live Activities match a session snapshot
/// (docs/LIVE_ACTIVITIES.md §5–6). Pure, so every reconciliation case is unit tested; the
/// app's `LiveActivityCoordinator` only executes the returned actions.
///
/// Order of truth is SwiftData → snapshot → Live Activity, never the reverse.
public struct LiveActivityPlanner: Sendable {
    /// How long an ended session's summary stays on the Lock Screen.
    public var endedSummaryDuration: TimeInterval
    /// After this long without a change, the content goes stale and the views show
    /// "Still feeding? Open Newbee". Should equal the engine's `RecoveryPolicy` threshold so the
    /// Lock Screen nudges exactly when the app would ask.
    public var staleAfter: TimeInterval

    public init(endedSummaryDuration: TimeInterval = 15 * 60, staleAfter: TimeInterval = 45 * 60) {
        self.endedSummaryDuration = endedSummaryDuration
        self.staleAfter = staleAfter
    }

    /// - Parameters:
    ///   - snapshot: The active session, a just-completed session (to show its summary), or `nil`.
    ///   - existing: Every activity of ours the system currently reports.
    ///   - activitiesEnabled: `ActivityAuthorizationInfo().areActivitiesEnabled`.
    ///   - dismissedAtRevision: If the parent swiped this session's activity away, the revision it
    ///     showed then. We don't bring it back until the session changes again.
    ///   - babyName: Shown in the activity's header; `""` for a generic title.
    ///   - now: Current time, used for the ended summary's dismissal date.
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
            // Session discarded or none active: clear running activities. A finished feed's
            // summary is left to time out on its own.
            return live.map(Self.removeNow)
        }

        let state = FeedingActivityAttributes.ContentState(snapshot: snapshot)
        let staleDate = state.staleDate(after: staleAfter)
        let mine = live.filter { $0.sessionID == snapshot.id }
        // Running activities for any other session are stale leftovers.
        var actions = live.filter { $0.sessionID != snapshot.id }.map(Self.removeNow)

        if snapshot.status == .completed {
            actions += ended.filter { $0.sessionID != snapshot.id }.map(Self.removeNow)
            let dismissal = LiveActivityDismissal.after(now.addingTimeInterval(endedSummaryDuration))
            actions += mine.map { .end(id: $0.id, finalState: state, dismissal: dismissal) }
            return actions
        }

        // Active or paused: any summary still on screen is now wrong, whether it belongs to the
        // previous feed (next feed started within the summary window) or to this one (End undone).
        actions += ended.map(Self.removeNow)

        // Keep exactly one live activity for this session.
        guard let keep = mine.max(by: { $0.state.revision < $1.state.revision }) else {
            let userDismissedThisState = dismissedAtRevision.map { snapshot.revision <= $0 } ?? false
            if activitiesEnabled && !userDismissedThisState {
                let attributes = FeedingActivityAttributes(sessionID: snapshot.id, babyName: babyName)
                actions.append(.request(attributes, state, staleDate: staleDate))
            }
            return actions
        }

        actions += mine.filter { $0.id != keep.id }.map(Self.removeNow)

        // Never move an activity backwards to an older revision.
        if keep.state != state && keep.state.revision <= state.revision {
            actions.append(.update(id: keep.id, state, staleDate: staleDate))
        }
        return actions
    }

    private static func removeNow(_ record: LiveActivityRecord) -> LiveActivityAction {
        .end(id: record.id, finalState: nil, dismissal: .immediate)
    }
}
