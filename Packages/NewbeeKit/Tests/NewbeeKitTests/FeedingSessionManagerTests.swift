import Foundation
import Testing
@testable import NewbeeKit

/// Records what the manager asked of the Live Activity and checks it only happens after saving.
@MainActor
final class RecordingLiveActivity: LiveActivitySyncing {
    var synced: [SessionSnapshot?] = []
    /// When set, checks at every sync that the store already holds what is being synced.
    var repository: InMemoryFeedingRepository?
    var sawUnsavedState = false

    func sync(_ snapshot: SessionSnapshot?) async {
        if let repository, let snapshot, repository.sessions[snapshot.id] != snapshot {
            sawUnsavedState = true
        }
        // Yield so overlapping commands would interleave if effects weren't serialized.
        await Task.yield()
        synced.append(snapshot)
    }
}

@MainActor
final class RecordingReminders: ReminderScheduling {
    var calls = 0
    var lastActive: SessionSnapshot??
    func feedingDataDidChange(activeSession: SessionSnapshot?, lastCompletedSession: SessionSnapshot?) async {
        calls += 1
        lastActive = .some(activeSession)
    }
}

struct DiskFull: Error {}

/// Simulates a Lock Screen "End" landing while recovery awaits the Live Activity sync.
@MainActor
final class EndingDuringSync: LiveActivitySyncing {
    weak var manager: FeedingSessionManager?
    private var fired = false

    func sync(_ snapshot: SessionSnapshot?) async {
        await Task.yield()
        guard !fired, let manager, snapshot?.status == .active else { return }
        fired = true
        _ = try? manager.end()
    }
}

@MainActor
@Suite("FeedingSessionManager")
struct FeedingSessionManagerTests {
    let clock = TestClock()
    let repository = InMemoryFeedingRepository()
    let activity = RecordingLiveActivity()
    let reminders = RecordingReminders()

    func makeManager() -> FeedingSessionManager {
        activity.repository = repository
        return FeedingSessionManager(repository: repository, clock: clock, liveActivity: activity, reminders: reminders)
    }

    @Test func startPersistsBeforePublishingAndSyncing() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let stored = try #require(try repository.activeSession())
        #expect(manager.activeSession == stored)
        await manager.waitForPendingEffects()
        #expect(activity.synced == [stored])
        #expect(!activity.sawUnsavedState)
        #expect(reminders.calls == 1)
    }

    @Test func fullFeedIsStoredAsSegments() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        clock.advance(by: 12 * 60)
        try manager.switchSide(to: .right)
        clock.advance(by: 9 * 60)
        let before = try manager.end()
        #expect(before.status == .active)
        #expect(manager.activeSession == nil)
        let done = try #require(manager.lastCompletedSession)
        #expect(done.status == .completed)
        #expect(done.duration(on: .left, at: clock.now) == 12 * 60)
        #expect(done.duration(on: .right, at: clock.now) == 9 * 60)
        #expect(try repository.session(id: done.id) == done)
        await manager.waitForPendingEffects()
        #expect(activity.synced.count == 3)
        #expect(activity.synced.last??.status == .completed)
    }

    @Test func secondStartThrowsAlreadyActiveAndCreatesNothing() throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let id = try #require(manager.activeSession?.id)
        #expect(throws: SessionEngineError.alreadyActive(id)) { try manager.start(side: .right) }
        #expect(repository.sessions.count == 1)
    }

    @Test func duplicateTapsAreSilentNoOpsWithNoSideEffects() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        await manager.waitForPendingEffects()
        let revision = manager.activeSession?.revision
        try manager.switchSide(to: .left)
        try manager.resume()
        await manager.waitForPendingEffects()
        #expect(manager.activeSession?.revision == revision)
        #expect(activity.synced.count == 1)
    }

    @Test func failedSaveChangesNothingAndRunsNoEffects() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        await manager.waitForPendingEffects()
        let before = manager.activeSession
        repository.simulatedFailure = DiskFull()
        clock.advance(by: 60)
        #expect(throws: FeedingSessionError.self) { try manager.switchSide(to: .right) }
        await manager.waitForPendingEffects()
        #expect(manager.activeSession == before)
        #expect(activity.synced.count == 1)
        repository.simulatedFailure = nil
        #expect(try repository.activeSession() == before)
    }

    @Test func commandsReadTheStoreNotCachedState() throws {
        // Another writer (for example an intent handled by a second manager instance) changed the store.
        let manager = makeManager()
        try manager.start(side: .left)
        let other = FeedingSessionManager(repository: repository, clock: clock)
        clock.advance(by: 60)
        try other.switchSide(to: .right)
        clock.advance(by: 60)
        try manager.switchSide(to: .right)   // the store already says right: a no-op, not a new segment
        #expect(try repository.activeSession()?.segments.count == 2)
    }

    @Test func effectsRunInCommandOrder() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        clock.advance(by: 5)
        try manager.switchSide(to: .right)
        clock.advance(by: 5)
        try manager.pause()
        clock.advance(by: 5)
        try manager.end()
        await manager.waitForPendingEffects()
        #expect(activity.synced.map { $0?.revision } == [1, 2, 3, 4])
        #expect(activity.synced.map { $0?.status } == [.active, .active, .paused, .completed])
    }

    @Test func suggestedSideIsOppositeOfTheLastSideUsed() throws {
        let manager = makeManager()
        #expect(manager.suggestedNextSide == .left)
        #expect(manager.lastSide == nil)
        try manager.start(side: .left)
        clock.advance(by: 300)
        try manager.switchSide(to: .right)
        clock.advance(by: 300)
        try manager.end()
        #expect(manager.lastSide == .right)
        #expect(manager.suggestedNextSide == .left)

        // A fresh manager (app relaunch) remembers it from the store.
        let relaunched = FeedingSessionManager(repository: repository, clock: clock)
        #expect(relaunched.lastSide == .right)
        #expect(relaunched.suggestedNextSide == .left)
    }

    @Test func relaunchRestoresTheActiveSessionFromTheStore() throws {
        let manager = makeManager()
        try manager.start(side: .right)
        clock.advance(by: 25 * 60)
        let relaunched = FeedingSessionManager(repository: repository, clock: clock)
        #expect(relaunched.activeSession == manager.activeSession)
        #expect(approx(relaunched.activeSession?.feedingDuration(at: clock.now), 25 * 60))
    }

    @Test func undoEndRestoresTheRunningSessionWithANewerRevision() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        clock.advance(by: 300)
        let before = try manager.end()
        clock.advance(by: 4)
        try manager.restore(before)
        let restored = try #require(manager.activeSession)
        #expect(restored.status == .active)
        #expect(restored.segments == before.segments)
        #expect(restored.revision == 3)
        #expect(manager.lastCompletedSession == nil)
        await manager.waitForPendingEffects()
        #expect(activity.synced.last??.status == .active)
    }

    @Test func discardAndUndoDiscard() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        clock.advance(by: 60)
        let discarded = try manager.discardActive()
        #expect(manager.activeSession == nil)
        #expect(repository.sessions.isEmpty)
        await manager.waitForPendingEffects()
        #expect(activity.synced.last == .some(nil))

        try manager.restore(discarded)
        #expect(manager.activeSession?.id == discarded.id)
        #expect(manager.activeSession!.revision > discarded.revision)
    }

    @Test func restoreRefusesToCreateASecondActiveSession() throws {
        let manager = makeManager()
        try manager.start(side: .left)
        clock.advance(by: 60)
        let first = try manager.end()
        clock.advance(by: 60)
        try manager.start(side: .right)
        #expect(throws: FeedingSessionError.conflictingSession(manager.activeSession!.id)) {
            try manager.restore(first)
        }
    }

    @Test func endWithEarlierTimeMarksEstimate() throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let start = clock.now
        clock.advance(by: 2 * 3600)
        try manager.end(at: start.addingTimeInterval(14 * 60))
        #expect(approx(manager.lastCompletedSession?.feedingDuration(at: clock.now), 14 * 60))
        #expect(manager.lastCompletedSession?.source == .recovered)
    }

    @Test func endWithoutSessionThrows() {
        let manager = makeManager()
        #expect(throws: SessionEngineError.noActiveSession) { try manager.end() }
        #expect(throws: SessionEngineError.noActiveSession) { try manager.discardActive() }
    }

    @Test func saveEditValidatesAndMarksManual() throws {
        let manager = makeManager()
        try manager.start(side: .left)
        clock.advance(by: 600)
        try manager.end()
        var edited = try #require(manager.lastCompletedSession)
        edited.segments[0].end = edited.segments[0].start.addingTimeInterval(300)
        edited.endedAt = edited.segments[0].end
        try manager.saveEdit(edited)
        let saved = try #require(try repository.session(id: edited.id))
        #expect(approx(saved.feedingDuration(at: clock.now), 300))
        #expect(saved.source == .manual)
        #expect(saved.revision == edited.revision + 1)

        var broken = saved
        broken.segments[0].end = broken.segments[0].start.addingTimeInterval(-10)
        #expect(throws: FeedingSessionError.self) { try manager.saveEdit(broken) }

        var reopened = saved
        reopened.status = .active
        #expect(throws: FeedingSessionError.statusChangeNotAllowed) { try manager.saveEdit(reopened) }
    }

    // MARK: Live Activity commands

    @Test func remoteCommandForTheActiveSessionApplies() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let id = manager.activeSession!.id
        clock.advance(by: 120)
        await manager.applyRemote(.switchTo(.right), sessionID: id)
        #expect(manager.activeSession?.openSegment?.side == .right)
        #expect(activity.synced.last??.openSegment?.side == .right)
    }

    @Test func remoteCommandReplayedTwiceIsIdempotent() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let id = manager.activeSession!.id
        clock.advance(by: 120)
        await manager.applyRemote(.pause, sessionID: id)
        await manager.applyRemote(.pause, sessionID: id)
        #expect(manager.activeSession?.status == .paused)
        #expect(manager.activeSession?.revision == 2)
    }

    @Test func remoteCommandForAStaleSessionIsIgnoredButResyncs() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let current = manager.activeSession!
        await manager.waitForPendingEffects()
        await manager.applyRemote(.end, sessionID: UUID())
        #expect(manager.activeSession == current)
        #expect(activity.synced.last == .some(current))
    }

    @Test func remoteEndAfterCompletionIsIgnored() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let id = manager.activeSession!.id
        clock.advance(by: 60)
        try manager.end()
        await manager.applyRemote(.end, sessionID: id)
        #expect(repository.sessions.count == 1)
        #expect(activity.synced.last == .some(nil))
    }

    // MARK: Undo End from the Live Activity summary

    @Test func undoEndPutsARunningFeedBackAsItWas() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let id = manager.activeSession!.id
        clock.advance(by: 5 * 60)
        await manager.applyRemote(.end, sessionID: id)
        #expect(manager.activeSession == nil)
        clock.advance(by: 30)
        await manager.undoEnd(sessionID: id)
        let reopened = try #require(manager.activeSession)
        #expect(reopened.id == id)
        #expect(reopened.status == .active)
        #expect(reopened.openSegment?.side == .left)
        #expect(reopened.endedAt == nil)
        #expect(approx(reopened.duration(on: .left, at: clock.now), 5 * 60 + 30))
        #expect(activity.synced.last == .some(reopened))
    }

    @Test func undoEndKeepsAPausedFeedPaused() async throws {
        let manager = makeManager()
        try manager.start(side: .right)
        let id = manager.activeSession!.id
        clock.advance(by: 4 * 60)
        try manager.pause()
        clock.advance(by: 10 * 60)
        await manager.applyRemote(.end, sessionID: id)
        await manager.undoEnd(sessionID: id)
        let reopened = try #require(manager.activeSession)
        #expect(reopened.status == .paused)
        #expect(approx(reopened.duration(on: .right, at: clock.now), 4 * 60))
    }

    @Test func undoEndAfterTheAppWasTerminatedReopensPaused() async throws {
        let first = makeManager()
        try first.start(side: .left)
        let id = first.activeSession!.id
        clock.advance(by: 6 * 60)
        await first.applyRemote(.end, sessionID: id)

        let relaunched = makeManager()
        clock.advance(by: 60)
        await relaunched.undoEnd(sessionID: id)
        let reopened = try #require(relaunched.activeSession)
        #expect(reopened.status == .paused)
        #expect(reopened.endedAt == nil)
        #expect(approx(reopened.duration(on: .left, at: clock.now), 6 * 60))
    }

    @Test func undoEndIsRefusedAfterTheWindow() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let id = manager.activeSession!.id
        clock.advance(by: 60)
        await manager.applyRemote(.end, sessionID: id)
        clock.advance(by: FeedingSessionManager.undoEndWindow + 1)
        await manager.undoEnd(sessionID: id)
        #expect(manager.activeSession == nil)
        #expect(try repository.session(id: id)?.status == .completed)
    }

    @Test func undoEndIsRefusedOnceTheNextFeedHasStarted() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let id = manager.activeSession!.id
        clock.advance(by: 60)
        await manager.applyRemote(.end, sessionID: id)
        clock.advance(by: 60)
        try manager.start(side: .right)
        let next = manager.activeSession
        await manager.undoEnd(sessionID: id)
        #expect(manager.activeSession == next)
        #expect(try repository.session(id: id)?.status == .completed)
    }

    @Test func undoEndTwiceIsHarmless() async throws {
        let manager = makeManager()
        try manager.start(side: .left)
        let id = manager.activeSession!.id
        clock.advance(by: 60)
        await manager.applyRemote(.end, sessionID: id)
        await manager.undoEnd(sessionID: id)
        let reopened = manager.activeSession
        await manager.undoEnd(sessionID: id)
        #expect(manager.activeSession == reopened)
        #expect(repository.sessions.count == 1)
    }
}

@MainActor
@Suite("RecoveryCoordinator")
struct RecoveryCoordinatorTests {
    let clock = TestClock()
    let engine = SessionEngine()

    @Test func reconcileOnLaunchRestoresAndSyncsTheActivity() async throws {
        let s = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        let repository = InMemoryFeedingRepository(sessions: [s])
        let activity = RecordingLiveActivity()
        clock.advance(by: 10 * 60)
        let manager = FeedingSessionManager(repository: repository, clock: clock, liveActivity: activity)
        let recovery = RecoveryCoordinator(manager: manager)
        await recovery.reconcile()
        #expect(manager.activeSession == s)
        #expect(manager.recoveryPrompt == nil)
        #expect(activity.synced == [s])
    }

    @Test func forgottenTimerPromptsAndKeepGoingDismisses() async throws {
        let s = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        let repository = InMemoryFeedingRepository(sessions: [s])
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        let recovery = RecoveryCoordinator(manager: manager)
        clock.advance(by: 3 * 3600)
        await recovery.reconcile()
        #expect(manager.recoveryPrompt?.reason == .longRunning)

        manager.dismissRecovery()
        #expect(manager.recoveryPrompt == nil)
        await recovery.reconcile()
        #expect(manager.recoveryPrompt == nil)
        // Never discarded automatically, and the feed itself is unchanged.
        #expect(manager.activeSession?.segments == s.segments)
        #expect(manager.activeSession?.revision == s.revision)

        // The answer survives the app being terminated and relaunched.
        clock.advance(by: 10 * 60)
        let relaunched = FeedingSessionManager(repository: repository, clock: clock)
        await RecoveryCoordinator(manager: relaunched).reconcile()
        #expect(relaunched.recoveryPrompt == nil)
        // …and "still feeding?" counts again from the answer.
        clock.advance(by: 40 * 60)
        await RecoveryCoordinator(manager: relaunched).reconcile()
        #expect(relaunched.recoveryPrompt?.reason == .longRunning)
    }

    @Test func backwardsClockChangeOnAMultiSegmentFeedIsFixable() async throws {
        // L 9:00–9:55, R from 10:00; at 10:30 the clock is set back 2 h.
        let repository = InMemoryFeedingRepository()
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        let recovery = RecoveryCoordinator(manager: manager)
        try manager.start(side: .left)
        clock.advance(by: 55 * 60)
        try manager.pause()
        clock.advance(by: 5 * 60)
        try manager.switchSide(to: .right)
        clock.advance(by: 30 * 60)
        clock.jumpWall(by: -2 * 3600)

        await recovery.reconcile()
        let prompt = try #require(manager.recoveryPrompt)
        #expect(prompt.reason == .clockChanged)
        #expect(SessionEngine.endTimeRange(for: prompt.session, now: clock.now) == nil)

        try manager.adjustStart(to: try #require(prompt.correctedStart))
        let fixed = try #require(manager.activeSession)
        #expect(approx(fixed.segments[0].duration(at: clock.now), 55 * 60))
        #expect(approx(fixed.duration(on: .right, at: clock.now), 30 * 60))
        #expect(SessionValidator.isValid(fixed, now: clock.now))
        await recovery.reconcile()
        #expect(manager.recoveryPrompt == nil)

        try manager.end()
        #expect(approx(manager.lastCompletedSession?.feedingDuration(at: clock.now), 85 * 60))
    }

    @Test func futureStartAfterARebootOffersAFixAndEndingWorksAfterIt() async throws {
        let repository = InMemoryFeedingRepository()
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        let recovery = RecoveryCoordinator(manager: manager)
        try manager.start(side: .left)
        clock.advance(by: 10 * 60)
        try manager.switchSide(to: .right)
        clock.advance(by: 5 * 60)
        clock.reboot()
        clock.jumpWall(by: -3600)

        await recovery.reconcile()
        let prompt = try #require(manager.recoveryPrompt)
        #expect(prompt.reason == .futureStart)
        #expect(prompt.correctedStart == clock.now)

        try manager.adjustStart(to: prompt.correctedStart!)
        #expect(manager.activeSession?.openSegment?.start == clock.now)
        #expect(approx(manager.activeSession?.duration(on: .left, at: clock.now), 10 * 60))
        clock.advance(by: 120)
        try manager.end()
        let done = try #require(manager.lastCompletedSession)
        #expect(SessionValidator.isValid(done, now: clock.now))
        #expect(approx(done.duration(on: .right, at: clock.now), 120))
    }

    @Test func promptIsNotPublishedForASessionThatChangedDuringTheActivitySync() async throws {
        let s = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        let repository = InMemoryFeedingRepository(sessions: [s])
        let activity = EndingDuringSync()
        let manager = FeedingSessionManager(repository: repository, clock: clock, liveActivity: activity)
        activity.manager = manager
        clock.advance(by: 3 * 3600)
        await RecoveryCoordinator(manager: manager).reconcile()
        #expect(manager.activeSession == nil)
        #expect(manager.recoveryPrompt == nil)
    }

    @Test func endingAtTheSuggestedTimeResolvesThePrompt() async throws {
        // Seed history so the suggestion uses this baby's typical segment (8 min).
        let t0 = clock.now.addingTimeInterval(-86_400)
        let history = SessionSnapshot(
            status: .completed,
            segments: [Segment(side: .right, start: t0, end: t0 + 480)],
            startedAt: t0, endedAt: t0 + 480
        )
        let s = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        let repository = InMemoryFeedingRepository(sessions: [history, s])
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        let recovery = RecoveryCoordinator(manager: manager)
        clock.advance(by: 4 * 3600)
        await recovery.reconcile()
        let prompt = try #require(manager.recoveryPrompt)
        #expect(prompt.suggestedEnd == s.startedAt + 480)

        try manager.end(at: prompt.suggestedEnd)
        #expect(manager.recoveryPrompt == nil)
        #expect(approx(manager.lastCompletedSession?.feedingDuration(at: clock.now), 480))
        #expect(manager.lastCompletedSession?.source == .recovered)
    }

    @Test func clockChangeIsFlaggedPersistedAndCorrectable() async throws {
        let s = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        let repository = InMemoryFeedingRepository(sessions: [s])
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        let recovery = RecoveryCoordinator(manager: manager)
        clock.advance(by: 7 * 60)
        clock.jumpWall(by: 3600)
        await recovery.reconcile()
        let prompt = try #require(manager.recoveryPrompt)
        #expect(prompt.reason == .clockChanged)
        #expect(try repository.activeSession()?.needsReview == true)

        try manager.adjustStart(to: try #require(prompt.correctedStart))
        #expect(approx(manager.activeSession?.feedingDuration(at: clock.now), 7 * 60))
        await recovery.reconcile()
        #expect(manager.recoveryPrompt == nil)
    }

    @Test func duplicatesAreRepairedOnLaunch() async throws {
        let a = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 600)
        let b = try engine.apply(.start(.right), to: nil, at: clock.instant()).snapshot
        let repository = InMemoryFeedingRepository(sessions: [a, b])
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        await RecoveryCoordinator(manager: manager).reconcile()
        #expect(try repository.openSessions().map(\.id) == [b.id])
        #expect(try repository.session(id: a.id)?.needsReview == true)
        #expect(manager.activeSession?.id == b.id)
        #expect(manager.lastCompletedSession?.id == a.id)
    }

    @Test func storeFailureIsReportedWithoutLosingState() async throws {
        let clock = TestClock()
        let a = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 600)
        let b = try engine.apply(.start(.right), to: nil, at: clock.instant()).snapshot
        let repository = InMemoryFeedingRepository(sessions: [a, b])
        repository.simulatedFailure = DiskFull()
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        let recovery = RecoveryCoordinator(manager: manager)
        await recovery.reconcile()
        #expect(recovery.lastError != nil)
        #expect(try repository.openSessions().count == 2)
    }
}
