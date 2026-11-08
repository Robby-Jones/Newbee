import Foundation
import Observation

/// Failures that are not engine rejections.
public enum FeedingSessionError: Error, Sendable, Hashable, LocalizedError {
    /// Reading or writing the store failed. Nothing was changed and no side effects ran.
    case persistence(String)
    /// An edited session breaks the session rules; nothing was saved.
    case invalidEdit([SessionInvariantViolation])
    /// An edit tried to change a running session's status; use the commands instead.
    case statusChangeNotAllowed
    /// The session to edit no longer exists.
    case sessionNotFound(UUID)
    /// Restoring would create a second active or paused session.
    case conflictingSession(UUID)

    public var errorDescription: String? {
        switch self {
        case .persistence: "Your feeding couldn't be saved. Please try again."
        case .invalidEdit: "Those times overlap or are out of order."
        case .statusChangeNotAllowed: "Use the timer controls to pause, resume or end a running feed."
        case .sessionNotFound: "That feeding no longer exists."
        case .conflictingSession: "Another feeding is already in progress."
        }
    }
}

/// The single owner of the active breastfeeding session (docs/TIMER_ENGINE.md §4).
///
/// Every command follows the same path, on the main actor so nothing can interleave:
/// 1. read the current session fresh from the store (never from cached UI state);
/// 2. run the pure `SessionEngine`;
/// 3. save, **before** any side effect; if the save fails, throw and do nothing else;
/// 4. publish `activeSession` for the UI;
/// 5. queue side effects (Live Activity, reminders), which run in command order.
///
/// Commands are synchronous so buttons can call them directly. Engine rejections throw
/// `SessionEngineError` (the UI treats `.alreadyActive` as success); storage failures throw
/// `FeedingSessionError`. Repeated commands (double taps, replayed intents) are silent no-ops.
@MainActor
@Observable
public final class FeedingSessionManager {
    /// The running or paused session, or `nil` when no feed is in progress.
    public private(set) var activeSession: SessionSnapshot?
    /// The most recent finished session, for "last side" and the summary after End.
    public private(set) var lastCompletedSession: SessionSnapshot?
    /// Set by `RecoveryCoordinator` when the parent must confirm what happened ("Were you still
    /// feeding?"). Cleared by `dismissRecovery()` or by any accepted command.
    public internal(set) var recoveryPrompt: RecoveryPrompt?

    @ObservationIgnored public let clock: any AppClock
    @ObservationIgnored let repository: any FeedingRepository
    @ObservationIgnored private let engine: SessionEngine
    @ObservationIgnored private let liveActivity: any LiveActivitySyncing
    @ObservationIgnored private let reminders: any ReminderScheduling
    /// Read only for the Live Activity: a bottle can be the latest feed it counts from.
    @ObservationIgnored private let bottles: (any BottleRepository)?
    @ObservationIgnored private var effectsTail: Task<Void, Never>?
    /// Session ID → when the parent answered "Keep going" (consumed by `RecoveryCoordinator`).
    @ObservationIgnored var recoveryAcknowledgements: [UUID: Date] = [:]

    public init(
        repository: any FeedingRepository,
        clock: any AppClock,
        liveActivity: (any LiveActivitySyncing)? = nil,
        reminders: (any ReminderScheduling)? = nil,
        bottles: (any BottleRepository)? = nil,
        engine: SessionEngine = SessionEngine()
    ) {
        self.repository = repository
        self.bottles = bottles
        self.clock = clock
        self.liveActivity = liveActivity ?? NoLiveActivities()
        self.reminders = reminders ?? NoReminders()
        self.engine = engine
        try? refresh()
    }

    // MARK: - Derived state

    /// The side used most recently (running side while feeding).
    public var lastSide: Side? {
        activeSession?.lastSide ?? lastCompletedSession?.lastSide
    }

    /// The side to offer next: the opposite of the side used last. Left when there's no history.
    public var suggestedNextSide: Side {
        lastSide?.opposite ?? .left
    }

    /// What the Live Activity shows: the running or paused feed, or else the last finished one
    /// (as time since it ended), or nothing.
    var liveActivitySnapshot: SessionSnapshot? {
        activeSession ?? lastCompletedSession
    }

    // MARK: - Commands

    public func start(side: Side) throws {
        try perform(.start(side))
    }

    public func switchSide(to side: Side) throws {
        try perform(.switchTo(side))
    }

    public func pause() throws {
        try perform(.pause)
    }

    public func resume() throws {
        try perform(.resume)
    }

    /// Ends the active session now, or at `date` (which marks its end as estimated).
    /// - Returns: the session as it was *before* ending, so the UI can offer undo via `restore`.
    @discardableResult
    public func end(at date: Date? = nil) throws -> SessionSnapshot {
        guard let before = try read({ try repository.activeSession() }) else {
            throw SessionEngineError.noActiveSession
        }
        try perform(date.map(SessionCommand.endAt) ?? .end)
        return before
    }

    /// Recovery's "Fix start time" (`RecoveryPrompt.correctedStart`): moves the running segment's
    /// start, or the pause time of a paused session, to `date`. Every other timestamp moves by the
    /// same offset, because a clock change puts *all* stored times in the old frame; segment
    /// lengths and order are kept.
    public func adjustStart(to date: Date) throws {
        guard let session = try read({ try repository.activeSession() }) else {
            throw SessionEngineError.noActiveSession
        }
        let reference = (session.status == .active ? session.openSegment?.start : nil)
            ?? session.segments.compactMap(\.end).max()
            ?? session.startedAt
        try perform(.shiftTimestamps(by: date.timeIntervalSince(reference)))
    }

    /// Deletes the active session.
    /// - Returns: the deleted session, so the UI can offer undo via `restore`.
    @discardableResult
    public func discardActive() throws -> SessionSnapshot {
        guard let session = try read({ try repository.activeSession() }) else {
            throw SessionEngineError.noActiveSession
        }
        try write { try repository.delete(sessionID: session.id) }
        recoveryPrompt = nil
        try? refresh()
        // Back to counting the time since the previous feed, if there was one.
        enqueueEffects(activity: .sync(liveActivitySnapshot), reminders: true)
        return session
    }

    /// Deletes a finished breastfeed (History's Delete). A running feed is removed with
    /// `discardActive()` instead, so the Live Activity ends with it.
    /// - Returns: the deleted session, so the UI can offer undo via `restore`.
    @discardableResult
    public func deleteCompleted(sessionID: UUID) throws -> SessionSnapshot {
        guard let session = try read({ try repository.session(id: sessionID) }) else {
            throw FeedingSessionError.sessionNotFound(sessionID)
        }
        guard session.status == .completed else { throw FeedingSessionError.statusChangeNotAllowed }
        try write { try repository.delete(sessionID: sessionID) }
        try? refresh()
        // "Last side", reminders and the since-last-feed count may now come from an earlier feed.
        enqueueEffects(activity: .sync(liveActivitySnapshot), reminders: true)
        return session
    }

    /// Writes `snapshot` back (undo of end, switch or discard) with a new revision.
    /// Refused if it would create a second active or paused session.
    public func restore(_ snapshot: SessionSnapshot) throws {
        let now = clock.now
        if snapshot.status != .completed,
           let other = try read({ try repository.openSessions() }).first(where: { $0.id != snapshot.id }) {
            throw FeedingSessionError.conflictingSession(other.id)
        }
        let violations = SessionValidator.violations(in: snapshot, now: now)
        guard violations.isEmpty else { throw FeedingSessionError.invalidEdit(violations) }
        let stored = try read { try repository.session(id: snapshot.id) }
        var restored = snapshot
        restored.revision = max(snapshot.revision, stored?.revision ?? 0) + 1
        try write { try repository.save(restored, modifiedAt: now) }
        recoveryPrompt = nil
        try? refresh()
        enqueueEffects(activity: .sync(restored.status == .completed ? liveActivitySnapshot : restored), reminders: true)
    }

    /// Saves a manually edited session after checking the same rules the engine enforces
    /// (docs/TIMER_ENGINE.md §7). A running session's status can't be changed by an edit.
    public func saveEdit(_ edited: SessionSnapshot) throws {
        let now = clock.now
        guard let stored = try read({ try repository.session(id: edited.id) }) else {
            throw FeedingSessionError.sessionNotFound(edited.id)
        }
        guard edited.status == stored.status else { throw FeedingSessionError.statusChangeNotAllowed }
        let violations = SessionValidator.violations(in: edited, now: now)
        guard violations.isEmpty else { throw FeedingSessionError.invalidEdit(violations) }
        var saved = edited
        saved.revision = stored.revision + 1
        if saved.source == .timer, saved.segments != stored.segments || saved.endedAt != stored.endedAt {
            saved.source = .manual
        }
        try write { try repository.save(saved, modifiedAt: now) }
        try? refresh()
        // An edited end time moves the since-last-feed count too.
        enqueueEffects(activity: .sync(saved.status == .completed ? liveActivitySnapshot : saved), reminders: true)
    }

    /// "Keep going": the parent confirmed the current state. Recovery won't ask about the same
    /// data again, and the "still feeding?" count restarts from now.
    /// The answer is saved on the session so it survives the app being terminated and relaunched.
    public func dismissRecovery() {
        defer { recoveryPrompt = nil }
        guard let prompt = recoveryPrompt else { return }
        let now = clock.now
        recoveryAcknowledgements[prompt.session.id] = now
        // Metadata only: the feed itself doesn't change, so the revision and Live Activity stay as they are.
        guard var session = try? repository.session(id: prompt.session.id), session.status != .completed else { return }
        session.recoveryAcknowledgedAt = now
        try? repository.save(session, modifiedAt: now)
        if activeSession?.id == session.id { activeSession = session }
    }

    // MARK: - Commands from outside the app UI (Live Activity buttons)

    /// Runs a command that names the session it was rendered for. A stale `sessionID` (an old
    /// Live Activity) is ignored. In every case the Live Activity is synced with the stored
    /// state before this returns, so stale activities are corrected.
    public func applyRemote(_ command: SessionCommand, sessionID: UUID) async {
        let current = try? repository.activeSession()
        var applied = false
        if let current, current.id == sessionID {
            applied = (try? perform(command))?.isNoOp == false
        }
        if !applied {
            try? refresh()
            enqueueEffects(activity: .sync(liveActivitySnapshot), reminders: false)
        }
        await waitForPendingEffects()
    }

    /// "Start" on the Live Activity's since-last-feed state, which was drawn for the finished feed
    /// `sessionID` (a breastfeed or a bottle). Ignored unless that is still the latest feed
    /// (`LatestFinishedFeed`) and none is running, so a tap on
    /// an out-of-date activity doesn't start a feed. Either way the Live Activity is synced before
    /// this returns, which corrects an out-of-date one.
    public func applyRemoteStart(side: Side, sessionID: UUID) async {
        try? refresh()
        let latest = LatestFinishedFeed.of(breast: lastCompletedSession, bottle: latestBottle())
        let current = activeSession == nil && latest?.id == sessionID
        if !current || (try? perform(.start(side)))?.isNoOp != false {
            try? refresh()
            enqueueEffects(activity: .sync(liveActivitySnapshot), reminders: false)
        }
        await waitForPendingEffects()
    }

    // MARK: - Loading

    /// Re-reads the active and last completed sessions from the store. No side effects.
    public func refresh() throws {
        activeSession = try read { try repository.activeSession() }
        lastCompletedSession = try read { try repository.recentCompletedSessions(limit: 1).first }
        if let prompt = recoveryPrompt, prompt.session.id != activeSession?.id {
            recoveryPrompt = nil
        }
    }

    /// Re-reads the store, then brings the Live Activity and reminders in line with it.
    /// Used at launch and on every foreground (via `RecoveryCoordinator`).
    public func reload() async {
        try? refresh()
        enqueueEffects(activity: .sync(liveActivitySnapshot), reminders: true)
        await waitForPendingEffects()
    }

    /// A bottle was logged, edited, deleted or restored. It may now be, or no longer be, the
    /// latest feed, so the since-last-feed count on the Live Activity is brought up to date.
    /// Bottles don't touch a running breastfeed; its activity is left as it is.
    public func bottlesDidChange() async {
        try? refresh()
        if activeSession == nil {
            enqueueEffects(activity: .sync(liveActivitySnapshot), reminders: false)
        }
        await waitForPendingEffects()
    }

    /// Waits until every queued Live Activity and reminder update has finished.
    public func waitForPendingEffects() async {
        await effectsTail?.value
    }

    // MARK: - Internals

    @discardableResult
    private func perform(_ command: SessionCommand) throws -> SessionTransition {
        let state = try read { try repository.activeSession() }
        let instant = clock.instant()
        let transition = try engine.apply(command, to: state, at: instant)
        guard !transition.isNoOp else { return transition }

        try write { try repository.save(transition.snapshot, modifiedAt: instant.wall) }

        if transition.snapshot.status == .completed {
            activeSession = nil
            lastCompletedSession = transition.snapshot
        } else {
            activeSession = transition.snapshot
        }
        recoveryPrompt = nil

        let effects = transition.effects
        let syncsActivity = effects.contains(.updateActivity) || effects.contains(.endActivity)
        enqueueEffects(
            activity: syncsActivity ? .sync(transition.snapshot) : .unchanged,
            reminders: effects.contains(.rescheduleReminders)
        )
        return transition
    }

    private enum ActivityUpdate {
        case unchanged
        case sync(SessionSnapshot?)
    }

    /// Queues side effects behind earlier ones so the Live Activity always sees changes in order.
    private func enqueueEffects(activity: ActivityUpdate, reminders shouldReschedule: Bool) {
        if case .unchanged = activity, !shouldReschedule { return }
        let previous = effectsTail
        let active = activeSession
        let lastCompleted = lastCompletedSession
        // Read now, in command order. Only matters when no feed is running.
        var lastBottle: BottleEntry?
        if case .sync(let snapshot) = activity, snapshot?.status ?? .completed == .completed {
            lastBottle = latestBottle()
        }
        effectsTail = Task { @MainActor [liveActivity, reminders, lastBottle] in
            await previous?.value
            if case .sync(let snapshot) = activity { await liveActivity.sync(snapshot, lastBottle: lastBottle) }
            if shouldReschedule {
                await reminders.feedingDataDidChange(activeSession: active, lastCompletedSession: lastCompleted)
            }
        }
    }

    private func latestBottle() -> BottleEntry? {
        (try? bottles?.recentBottles(limit: 1))?.first
    }

    private func read<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch { throw FeedingSessionError.persistence(String(describing: error)) }
    }

    private func write(_ body: () throws -> Void) throws {
        do { try body() } catch { throw FeedingSessionError.persistence(String(describing: error)) }
    }
}
