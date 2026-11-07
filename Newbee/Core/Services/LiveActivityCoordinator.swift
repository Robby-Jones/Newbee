import Foundation
import NewbeeKit
import NewbeeShared
import Observation
import os

/// Makes the system's Live Activities match the session manager's snapshot
/// (docs/LIVE_ACTIVITIES.md §5). `sync(_:)` is the only entry point.
///
/// - The session manager calls it after every saved command (active/paused snapshot, the
///   just-completed snapshot after End, or `nil` after discard).
/// - Recovery calls it on launch and every foreground, which re-requests an activity lost to a
///   reboot or the 8-hour limit and ends leftovers.
///
/// Decisions come from the pure `LiveActivityPlanner` (unit tested in NewbeeShared); this type
/// only serializes calls and executes the plan against ActivityKit.
@MainActor
@Observable
final class LiveActivityCoordinator {
    /// Whether Live Activities are allowed in iOS Settings. Drives the gentle in-app hint.
    private(set) var activitiesEnabled: Bool

    /// Name shown in the activity header; empty for a generic "Feeding".
    /// TODO(5b): set from the baby profile once onboarding stores a name.
    @ObservationIgnored var babyName = ""

    private let client: any LiveActivityClient
    private let clock: any AppClock
    private let planner: LiveActivityPlanner
    /// Session id → revision the parent swiped away. Not persisted: after a relaunch we show it again.
    @ObservationIgnored private var dismissedRevisions: [UUID: Int] = [:]
    /// The last queued sync. Each sync waits for the previous one so ActivityKit calls never interleave.
    @ObservationIgnored private var tail: Task<Void, Never>?
    private let logger = Logger(subsystem: "Newbee", category: "LiveActivity")

    init(
        client: any LiveActivityClient,
        clock: any AppClock = SystemClock(),
        planner: LiveActivityPlanner = LiveActivityPlanner()
    ) {
        self.client = client
        self.clock = clock
        self.planner = planner
        self.activitiesEnabled = client.areActivitiesEnabled
        client.onUserDismissal = { [weak self] sessionID, revision in
            self?.dismissedRevisions[sessionID] = revision
        }
        client.onEnablementChange = { [weak self] enabled in
            self?.activitiesEnabled = enabled
        }
    }

    convenience init() {
        self.init(client: ActivityKitClient())
    }

    /// Brings the Live Activity in line with `snapshot`. Safe to call repeatedly; returns once
    /// every ActivityKit call for this and earlier syncs has finished.
    func sync(_ snapshot: SessionSnapshot?) async {
        let previous = tail
        let task = Task { [weak self] in
            await previous?.value
            await self?.reconcile(snapshot)
        }
        tail = task
        await task.value
    }

    private func reconcile(_ snapshot: SessionSnapshot?) async {
        activitiesEnabled = client.areActivitiesEnabled
        let actions = planner.plan(
            for: snapshot,
            existing: client.records(),
            activitiesEnabled: activitiesEnabled,
            dismissedAtRevision: snapshot.flatMap { dismissedRevisions[$0.id] },
            babyName: babyName,
            now: clock.now
        )
        for action in actions {
            await perform(action)
        }
        if let snapshot, snapshot.status != .completed {
            dismissedRevisions = dismissedRevisions.filter { $0.key == snapshot.id }
        } else {
            dismissedRevisions.removeAll()
        }
    }

    private func perform(_ action: LiveActivityAction) async {
        switch action {
        case let .request(attributes, state, staleDate):
            do {
                _ = try client.request(attributes, state: state, staleDate: staleDate)
            } catch {
                // Expected when the app is in the background (e.g. a Lock Screen intent after a
                // reboot) or activities are off. Recovery requests it again on next foreground.
                logger.notice("Live Activity request refused: \(String(describing: error))")
            }
        case let .update(id, state, staleDate):
            await client.update(id: id, state: state, staleDate: staleDate)
        case let .end(id, finalState, dismissal):
            await client.end(id: id, finalState: finalState, dismissal: dismissal)
        }
    }
}
