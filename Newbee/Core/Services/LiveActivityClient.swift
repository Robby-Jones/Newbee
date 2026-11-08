import ActivityKit
import Foundation
import NewbeeShared
import os

/// The ActivityKit calls the coordinator needs, behind a protocol so the coordinator's
/// sequencing can be tested with a fake (ActivityKit itself can't be driven from unit tests).
@MainActor
protocol LiveActivityClient: AnyObject {
    /// `ActivityAuthorizationInfo().areActivitiesEnabled`.
    var areActivitiesEnabled: Bool { get }
    /// Called when the parent swipes an active activity away: (session id, revision it showed).
    var onUserDismissal: (@MainActor (UUID, Int) -> Void)? { get set }
    /// Called when the parent turns Live Activities on or off in Settings.
    var onEnablementChange: (@MainActor (Bool) -> Void)? { get set }

    func records() -> [LiveActivityRecord]
    /// Returns the new activity's id. Throws if the system refuses (disabled, app in background,
    /// too many activities).
    func request(
        _ attributes: FeedingActivityAttributes,
        state: FeedingActivityAttributes.ContentState,
        staleDate: Date
    ) throws -> String
    func update(id: String, state: FeedingActivityAttributes.ContentState, staleDate: Date) async
    func end(id: String, finalState: FeedingActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async
}

/// The real client.
@MainActor
final class ActivityKitClient: LiveActivityClient {
    typealias FeedingActivity = Activity<FeedingActivityAttributes>

    var onUserDismissal: (@MainActor (UUID, Int) -> Void)?
    var onEnablementChange: (@MainActor (Bool) -> Void)? {
        didSet { observeEnablementIfNeeded() }
    }

    private var stateObservers: [String: Task<Void, Never>] = [:]
    private var enablementObserver: Task<Void, Never>?
    private let logger = Logger(subsystem: "Newbee", category: "LiveActivity")

    init() {}

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func records() -> [LiveActivityRecord] {
        FeedingActivity.activities.map { activity in
            observeState(of: activity)
            let state = activity.content.state
            return LiveActivityRecord(
                id: activity.id,
                sessionID: LiveActivityRecord.sessionID(attributes: activity.attributes, state: state),
                requestedForSessionID: activity.attributes.sessionID,
                state: state,
                phase: Self.phase(of: activity.activityState)
            )
        }
    }

    func request(
        _ attributes: FeedingActivityAttributes,
        state: FeedingActivityAttributes.ContentState,
        staleDate: Date
    ) throws -> String {
        let activity = try FeedingActivity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: staleDate),
            pushType: nil
        )
        observeState(of: activity)
        return activity.id
    }

    func update(id: String, state: FeedingActivityAttributes.ContentState, staleDate: Date) async {
        await Self.updateActivity(id: id, state: state, staleDate: staleDate)
    }

    func end(id: String, finalState: FeedingActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async {
        await Self.endActivity(id: id, finalState: finalState, dismissal: dismissal)
    }

    // `Activity` isn't Sendable, so its async calls are made from nonisolated helpers that look
    // the activity up themselves; only Sendable values cross from the main actor.
    private nonisolated static func updateActivity(
        id: String,
        state: FeedingActivityAttributes.ContentState,
        staleDate: Date
    ) async {
        guard let activity = FeedingActivity.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    private nonisolated static func endActivity(
        id: String,
        finalState: FeedingActivityAttributes.ContentState?,
        dismissal: LiveActivityDismissal
    ) async {
        guard let activity = FeedingActivity.activities.first(where: { $0.id == id }) else { return }
        let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = switch dismissal {
        case .immediate: .immediate
        case .after(let date): .after(date)
        }
        await activity.end(content, dismissalPolicy: policy)
    }

    private static func phase(of state: ActivityState) -> LiveActivityRecord.Phase {
        switch state {
        case .ended: .ended
        case .dismissed: .dismissed
        default: .live
        }
    }

    /// Detects the parent swiping the activity away (active → dismissed), as opposed to the
    /// system ending it (8-hour limit), so the coordinator doesn't immediately bring it back.
    private func observeState(of activity: FeedingActivity) {
        let id = activity.id
        guard stateObservers[id] == nil else { return }
        stateObservers[id] = Task { [weak self] in
            var previous = activity.activityState
            for await state in activity.activityStateUpdates {
                if state == .dismissed, previous == .active || previous == .stale {
                    let content = activity.content.state
                    let sessionID = LiveActivityRecord.sessionID(attributes: activity.attributes, state: content)
                    self?.onUserDismissal?(sessionID, content.revision)
                }
                previous = state
            }
            self?.stateObservers[id] = nil
        }
    }

    private func observeEnablementIfNeeded() {
        guard enablementObserver == nil, onEnablementChange != nil else { return }
        enablementObserver = Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                self?.onEnablementChange?(enabled)
            }
        }
    }
}
