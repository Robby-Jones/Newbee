import Foundation
import Observation

/// Launch, foreground and clock-change reconciliation (docs/TIMER_ENGINE.md §5,
/// docs/LIVE_ACTIVITIES.md §6). Order of truth: store → manager → Live Activity.
///
/// `reconcile()` is idempotent and cheap; call it at launch, whenever the scene becomes active,
/// and on `NSSystemClockDidChange`. It never discards data: anything ambiguous becomes a
/// `RecoveryPrompt` on the manager, which the recovery sheet presents.
@MainActor
@Observable
public final class RecoveryCoordinator {
    /// How many recent sessions inform the suggested end time.
    public static let historySampleSize = 20

    @ObservationIgnored private let manager: FeedingSessionManager
    @ObservationIgnored private let planner: RecoveryPlanner
    @ObservationIgnored private var isReconciling = false
    @ObservationIgnored private var needsAnotherPass = false

    public init(manager: FeedingSessionManager, policy: RecoveryPolicy = RecoveryPolicy()) {
        self.manager = manager
        self.planner = RecoveryPlanner(policy: policy)
    }

    /// The last error from reading or repairing the store, if any (shown as a non-blocking banner).
    public private(set) var lastError: FeedingSessionError?

    public func reconcile() async {
        // Calls can arrive back to back (launch + scene activation); coalesce them.
        if isReconciling {
            needsAnotherPass = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            await reconcileOnce()
        } while needsAnotherPass
    }

    private func reconcileOnce() async {
        let repository = manager.repository
        let now = manager.clock.instant()
        do {
            let open = try repository.openSessions()
            let history = (try? repository.recentCompletedSessions(limit: Self.historySampleSize)) ?? []
            let plan = planner.plan(
                openSessions: open,
                at: now,
                typicalSegmentDuration: RecoveryPlanner.typicalSegmentDuration(from: history),
                acknowledged: manager.recoveryAcknowledgements
            )
            if !plan.updates.isEmpty {
                try repository.save(plan.updates, modifiedAt: now.wall)
            }
            lastError = nil
            await manager.reload()
            manager.recoveryPrompt = plan.prompt
        } catch {
            lastError = (error as? FeedingSessionError) ?? .persistence(String(describing: error))
            await manager.reload()
        }
    }
}
