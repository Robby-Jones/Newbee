import Foundation
import NewbeeKit
import Observation

/// An in-memory stand-in for `FeedingSessionManager`, used by SwiftUI previews and UI-model tests
/// until the real manager is wired in. It keeps nothing on disk.
///
/// It follows the engine's transition table (docs/TIMER_ENGINE.md §3) closely enough to exercise
/// every UI state, but it is not the engine and must never be used for real data.
@MainActor
@Observable
final class PreviewSessionController: FeedingSessionControlling {
    private(set) var activeSession: SessionSnapshot?
    private(set) var lastCompletedSession: SessionSnapshot?
    var recoveryPrompt: RecoveryPrompt?
    var now: () -> Date

    /// Every command received, for tests.
    private(set) var log: [String] = []

    init(
        activeSession: SessionSnapshot? = nil,
        lastCompletedSession: SessionSnapshot? = nil,
        recoveryPrompt: RecoveryPrompt? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.activeSession = activeSession
        self.lastCompletedSession = lastCompletedSession
        self.recoveryPrompt = recoveryPrompt
        self.now = now
    }

    var suggestedNextSide: Side {
        (lastCompletedSession?.lastSide ?? .right).opposite
    }

    func start(side: Side) throws {
        log.append("start(\(side.rawValue))")
        guard activeSession == nil else { throw PreviewSessionError.alreadyActive }
        let t = now()
        activeSession = SessionSnapshot(status: .active, segments: [Segment(side: side, start: t)], startedAt: t, revision: 1)
    }

    func switchSide(to side: Side) throws {
        log.append("switchSide(\(side.rawValue))")
        guard var s = activeSession else { throw PreviewSessionError.noActiveSession }
        let t = now()
        if s.status == .active {
            guard s.openSegment?.side != side else { return }
            closeOpenSegment(&s, at: t)
        }
        s.segments.append(Segment(side: side, start: t))
        s.status = .active
        s.revision += 1
        activeSession = s
    }

    func pause() throws {
        log.append("pause")
        guard var s = activeSession else { throw PreviewSessionError.noActiveSession }
        guard s.status == .active else { return }
        closeOpenSegment(&s, at: now())
        s.status = .paused
        s.revision += 1
        activeSession = s
    }

    func resume() throws {
        log.append("resume")
        guard var s = activeSession else { throw PreviewSessionError.noActiveSession }
        guard s.status == .paused, let side = s.lastSide else { return }
        s.segments.append(Segment(side: side, start: now()))
        s.status = .active
        s.revision += 1
        activeSession = s
    }

    func adjustStart(to date: Date) throws {
        log.append("adjustStart")
        guard var s = activeSession, !s.segments.isEmpty else { throw PreviewSessionError.noActiveSession }
        s.startedAt = date
        s.segments[0].start = date
        s.revision += 1
        activeSession = s
        recoveryPrompt = nil
    }

    @discardableResult
    func end(at date: Date?) throws -> SessionSnapshot {
        log.append("end")
        guard let before = activeSession else { throw PreviewSessionError.noActiveSession }
        var s = before
        let t = date ?? now()
        closeOpenSegment(&s, at: t)
        s.status = .completed
        s.endedAt = s.segments.last?.end ?? t
        s.revision += 1
        lastCompletedSession = s
        activeSession = nil
        recoveryPrompt = nil
        return before
    }

    @discardableResult
    func discardActive() throws -> SessionSnapshot {
        log.append("discard")
        guard let s = activeSession else { throw PreviewSessionError.noActiveSession }
        activeSession = nil
        recoveryPrompt = nil
        return s
    }

    func restore(_ snapshot: SessionSnapshot) throws {
        log.append("restore")
        if lastCompletedSession?.id == snapshot.id { lastCompletedSession = nil }
        activeSession = snapshot
    }

    func dismissRecovery() {
        log.append("dismissRecovery")
        recoveryPrompt = nil
    }

    private func closeOpenSegment(_ s: inout SessionSnapshot, at t: Date) {
        guard let i = s.segments.lastIndex(where: \.isOpen) else { return }
        s.segments[i].end = max(t, s.segments[i].start)
    }
}

// MARK: - Fixtures

extension PreviewSessionController {
    /// Left 12 min, now on the right for 6 min 37 s; previous feed ended on the right.
    static func activeFixture(now: Date = .now) -> PreviewSessionController {
        let start = now.addingTimeInterval(-(12 * 60 + 397))
        let switchAt = start.addingTimeInterval(12 * 60)
        return PreviewSessionController(
            activeSession: SessionSnapshot(
                status: .active,
                segments: [
                    Segment(side: .left, start: start, end: switchAt),
                    Segment(side: .right, start: switchAt),
                ],
                startedAt: start,
                revision: 2
            ),
            lastCompletedSession: completedFixture(endingBefore: start)
        )
    }

    static func pausedFixture(now: Date = .now) -> PreviewSessionController {
        let controller = activeFixture(now: now)
        try? controller.pause()
        return controller
    }

    static func idleFixture(now: Date = .now) -> PreviewSessionController {
        PreviewSessionController(lastCompletedSession: completedFixture(endingBefore: now.addingTimeInterval(-2 * 3600)))
    }

    static func recoveryFixture(now: Date = .now) -> PreviewSessionController {
        let start = now.addingTimeInterval(-(3 * 3600 + 12 * 60))
        let session = SessionSnapshot(status: .active, segments: [Segment(side: .left, start: start)], startedAt: start, revision: 1)
        return PreviewSessionController(
            activeSession: session,
            recoveryPrompt: RecoveryPrompt(session: session, suggestedEnd: start.addingTimeInterval(26 * 60), reason: .longRunning)
        )
    }

    /// The spec's example feed: left 12 min, right 9 min.
    static func completedFixture(endingBefore end: Date) -> SessionSnapshot {
        let start = end.addingTimeInterval(-21 * 60)
        let switchAt = start.addingTimeInterval(12 * 60)
        return SessionSnapshot(
            status: .completed,
            segments: [
                Segment(side: .left, start: start, end: switchAt),
                Segment(side: .right, start: switchAt, end: end),
            ],
            startedAt: start,
            endedAt: end,
            revision: 3
        )
    }
}
