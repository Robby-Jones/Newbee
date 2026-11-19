import Foundation
import NewbeeKit
import NewbeeShared
import Observation
import os

/// Makes the system's Live Activities match the session manager's snapshot
/// (docs/LIVE_ACTIVITIES.md §5). `sync(_:lastBottle:mode:)` is the only entry point.
///
/// - The session manager calls it after every saved command and every bottle change: the active
///   or paused snapshot, or, when no feed is running, the latest finished breastfeed and the latest
///   bottle (the activity then counts the time since the newer of the two ended). With no feeds
///   at all, both are `nil`.
/// - Recovery calls it on launch and every foreground, which re-requests a running feed's
///   activity lost to a reboot or the 8-hour limit and ends leftovers.
///
/// Decisions come from the pure `LiveActivityPlanner` (unit tested in NewbeeShared); this type
/// only serializes calls and executes the plan against ActivityKit.
@MainActor
@Observable
final class LiveActivityCoordinator {
    /// Whether Live Activities are allowed in iOS Settings. Drives the gentle in-app hint.
    private(set) var activitiesEnabled: Bool

    /// The baby's name from the profile, shown under the avatar once a feed has ended; empty when
    /// none is set. Read when an activity is requested (it's part of the activity's attributes).
    @ObservationIgnored var babyName: @MainActor () -> String = { "" }
    /// Settings' "Count from" (the since-last-feed count runs from the last feed's start or end),
    /// read at every sync. A change in Settings re-syncs (see `NewbeeApp`).
    @ObservationIgnored var countFrom: @MainActor () -> ReminderSettings.Basis = { .end }
    /// Settings' color theme, read at every sync: the Lock Screen card is blush in the pink
    /// theme. A change in Settings re-syncs (see `NewbeeApp`).
    @ObservationIgnored var theme: @MainActor () -> NBTheme = { .standard }
    /// Settings' "Suggested starting side", for the since-last-feed tint.
    @ObservationIgnored var startingSide: @MainActor () -> StartingSideSuggestion = { StartingSideSuggestion() }

    private let client: any LiveActivityClient
    private let clock: any AppClock
    private let planner: LiveActivityPlanner
    /// How long after Settings' refresh to check that iOS kept the new activity.
    private let refreshCheckDelay: Duration
    /// Session id → revision the parent swiped away. Not persisted: after a relaunch we show it again.
    @ObservationIgnored private var dismissedRevisions: [UUID: Int] = [:]
    /// The last queued sync. Each sync waits for the previous one so ActivityKit calls never interleave.
    @ObservationIgnored private var tail: Task<Void, Never>?
    private let logger = Logger(subsystem: "Newbee", category: "LiveActivity")

    init(
        client: any LiveActivityClient,
        clock: any AppClock = SystemClock(),
        planner: LiveActivityPlanner = LiveActivityPlanner(),
        refreshCheckDelay: Duration = .seconds(1)
    ) {
        self.client = client
        self.clock = clock
        self.planner = planner
        self.refreshCheckDelay = refreshCheckDelay
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

    /// Brings the Live Activity in line with `snapshot` (and `lastBottle` when no feed is
    /// running). `mode` says whether to bring back an activity that isn't showing
    /// (`LiveActivitySyncMode`). Safe to call repeatedly; returns once every ActivityKit call for
    /// this and earlier syncs has finished.
    func sync(_ snapshot: SessionSnapshot?, lastBottle: BottleEntry?, mode: LiveActivitySyncMode) async {
        _ = await enqueue(snapshot, lastBottle: lastBottle, mode: mode)
    }

    /// Settings' "Refresh Live Activity": a `.refresh` sync that reports how it went. When iOS
    /// accepts the request, checks a moment later that the activity is still running, since iOS
    /// drops one it can't draw without an error.
    func refresh(_ snapshot: SessionSnapshot?, lastBottle: BottleEntry?) async -> LiveActivityRefreshResult {
        await enqueue(snapshot, lastBottle: lastBottle, mode: .refresh)
    }

    private func enqueue(
        _ snapshot: SessionSnapshot?,
        lastBottle: BottleEntry?,
        mode: LiveActivitySyncMode
    ) async -> LiveActivityRefreshResult {
        let previous = tail
        let task = Task { [weak self] () -> LiveActivityRefreshResult in
            await previous?.value
            return await self?.reconcile(snapshot, lastBottle: lastBottle, mode: mode) ?? .nothingToShow
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    private func reconcile(
        _ snapshot: SessionSnapshot?,
        lastBottle: BottleEntry?,
        mode: LiveActivitySyncMode
    ) async -> LiveActivityRefreshResult {
        activitiesEnabled = client.areActivitiesEnabled
        let actions = planner.plan(
            for: snapshot,
            lastBottle: lastBottle,
            existing: client.records(),
            activitiesEnabled: activitiesEnabled,
            dismissedAtRevision: snapshot.flatMap { dismissedRevisions[$0.id] },
            babyName: babyName(),
            countFrom: countFrom(),
            theme: theme(),
            startingSide: startingSide(),
            mode: mode,
            now: clock.now
        )
        var result: LiveActivityRefreshResult = activitiesEnabled ? .nothingToShow : .disabled
        var requested: String?
        for action in actions {
            switch await perform(action) {
            case .requested(let id):
                requested = id
                result = .shown
            case .refused(let reason):
                result = .refused(reason)
            case .done:
                break
            }
        }
        if mode == .refresh, let requested {
            try? await Task.sleep(for: refreshCheckDelay)
            if client.records().first(where: { $0.id == requested })?.phase != .live {
                logger.error("Live Activity \(requested) was gone right after the refresh")
                result = .removedRightAway
            }
        }
        if mode != .update {
            // The parent asked for the activity back, so an earlier swipe no longer holds.
            dismissedRevisions.removeAll()
        } else if let snapshot, snapshot.status != .completed {
            dismissedRevisions = dismissedRevisions.filter { $0.key == snapshot.id }
        } else {
            dismissedRevisions.removeAll()
        }
        return result
    }

    private enum Outcome {
        case done
        case requested(id: String)
        case refused(reason: String)
    }

    private func perform(_ action: LiveActivityAction) async -> Outcome {
        switch action {
        case let .request(attributes, state, staleDate, replacing):
            do {
                let id = try client.request(attributes, state: state, staleDate: staleDate)
                // Only now remove the activity it replaces, so the parent never sees a gap.
                if let replacing {
                    await client.end(id: replacing, finalState: nil, dismissal: .immediate)
                }
                return .requested(id: id)
            } catch {
                // Expected when the app is in the background (e.g. Start on the Lock Screen, or
                // a Lock Screen intent after a reboot) or activities are off.
                logger.notice("Live Activity request refused: \(String(describing: error))")
                if let replacing {
                    // Keep the parent's activity by carrying it over to the new feed. Its
                    // content names the new session, so its buttons act on that feed.
                    await client.update(id: replacing, state: state, staleDate: staleDate)
                }
                // Otherwise recovery requests it again on the next foreground.
                return .refused(reason: Self.reason(for: error))
            }
        case let .update(id, state, staleDate):
            await client.update(id: id, state: state, staleDate: staleDate)
        case let .end(id, finalState, dismissal):
            await client.end(id: id, finalState: finalState, dismissal: dismissal)
        }
        return .done
    }

    /// iOS's own words for a refused request, for Settings to show.
    private static func reason(for error: any Error) -> String {
        if let error = error as? any LocalizedError {
            let parts = [error.errorDescription, error.failureReason].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return String(describing: error)
    }
}
