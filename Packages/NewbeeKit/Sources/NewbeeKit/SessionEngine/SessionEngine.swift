import Foundation

/// The breastfeeding session state machine (docs/TIMER_ENGINE.md §3).
///
/// Pure: `(state, command, now) → (new state, effects)` or an error. It never reads the clock,
/// touches storage or talks to ActivityKit, so every transition is deterministic and testable.
/// "Not started" is represented by `state == nil`.
public struct SessionEngine: Sendable {
    /// A segment shorter than this, created by a switch or pause, is treated as an accidental
    /// tap and merged away instead of being stored.
    public static let minimumSegmentDuration: TimeInterval = 1
    /// How far into the future a supplied time may be (clock skew between taps and "now").
    public static let futureTolerance: TimeInterval = 60

    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    public func apply(
        _ command: SessionCommand,
        to state: SessionSnapshot?,
        at now: Instant
    ) throws(SessionEngineError) -> SessionTransition {
        guard let state else {
            guard case .start(let side) = command else { throw .noActiveSession }
            return start(side, at: now)
        }
        if state.status == .completed { throw .alreadyCompleted(state.id) }

        // An active session whose open segment is missing (corrupt data) behaves like a paused one,
        // so every command still leads to a valid state.
        let isRunning = state.status == .active && state.openSegment != nil

        var next = state
        let effects: Set<SessionEffect>

        switch command {
        case .start:
            throw .alreadyActive(state.id)

        case .switchTo(let side):
            if isRunning {
                guard let open = state.openSegment, open.side != side else { return .noOp(state) }
                switchRunning(&next, to: side, at: now)
            } else {
                openSegment(&next, side: side, at: now)
            }
            effects = [.persist, .updateActivity, .rescheduleReminders]

        case .pause:
            guard isRunning else { return .noOp(state) }
            closeOpenSegment(&next, at: now.wall)
            next.status = .paused
            effects = [.persist, .updateActivity, .rescheduleReminders]

        case .resume:
            guard !isRunning else { return .noOp(state) }
            openSegment(&next, side: state.lastSide ?? .left, at: now)
            effects = [.persist, .updateActivity, .rescheduleReminders]

        case .end:
            let endedAt: Date
            if isRunning {
                closeOpenSegment(&next, at: now.wall)
                endedAt = now.wall
            } else {
                // Paused: the feed really ended when the last segment closed.
                endedAt = state.segments.last?.end ?? state.startedAt
            }
            complete(&next, at: endedAt)
            effects = [.persist, .endActivity, .rescheduleReminders]

        case .endAt(let date):
            let earliest = isRunning ? state.openSegment!.start : (state.segments.last?.end ?? state.startedAt)
            guard date >= earliest, date <= now.wall.addingTimeInterval(Self.futureTolerance) else {
                throw .invalidTime
            }
            if isRunning { closeOpenSegment(&next, at: date) }
            complete(&next, at: date)
            // The parent picked the end time after the fact, so it's an estimate.
            if next.source == .timer { next.source = .recovered }
            effects = [.persist, .endActivity, .rescheduleReminders]

        case .adjustOpenSegmentStart(let date):
            guard isRunning, let index = state.segments.lastIndex(where: \.isOpen) else {
                throw .noActiveSession
            }
            let previousEnd = index > 0 ? state.segments[index - 1].end : nil
            guard date <= now.wall, previousEnd.map({ date >= $0 }) ?? true else { throw .invalidTime }
            guard date != state.segments[index].start else { return .noOp(state) }
            next.segments[index].start = date
            next.segments[index].startMonotonic = now.monotonic.map { $0 - now.wall.timeIntervalSince(date) }
            next.segments[index].startBootID = now.bootID
            if index == 0 { next.startedAt = date }
            effects = [.persist, .updateActivity, .rescheduleReminders]
        }

        next.revision = state.revision + 1
        return SessionTransition(snapshot: next, effects: effects)
    }

    // MARK: - Transitions

    private func start(_ side: Side, at now: Instant) -> SessionTransition {
        let snapshot = SessionSnapshot(
            status: .active,
            segments: [Self.newSegment(side: side, at: now)],
            startedAt: now.wall,
            revision: 1,
            timeZoneID: timeZone.identifier,
            source: .timer
        )
        return SessionTransition(snapshot: snapshot, effects: [.persist, .updateActivity, .rescheduleReminders])
    }

    /// Active → active on the other side. Rapid taps (the running segment is shorter than
    /// `minimumSegmentDuration`) rewrite the running segment instead of storing junk segments.
    private func switchRunning(_ s: inout SessionSnapshot, to side: Side, at now: Instant) {
        guard let index = s.segments.lastIndex(where: \.isOpen) else { return }
        let open = s.segments[index]
        guard now.wall.timeIntervalSince(open.start) < Self.minimumSegmentDuration else {
            closeOpenSegment(&s, at: now.wall)
            s.segments.append(Self.newSegment(side: side, at: now))
            return
        }
        // L → R → L within a second: drop the blip and reopen the segment it interrupted.
        if index > 0, s.segments[index - 1].side == side, s.segments[index - 1].end == open.start {
            s.segments.remove(at: index)
            s.segments[index - 1].end = nil
        } else {
            s.segments[index].side = side
        }
    }

    private func openSegment(_ s: inout SessionSnapshot, side: Side, at now: Instant) {
        s.segments.append(Self.newSegment(side: side, at: now))
        s.status = .active
    }

    /// Closes the running segment at `end`. A segment shorter than the minimum is dropped
    /// unless it is the only one (a session always keeps at least one segment).
    private func closeOpenSegment(_ s: inout SessionSnapshot, at end: Date) {
        guard let index = s.segments.lastIndex(where: \.isOpen) else { return }
        let start = s.segments[index].start
        if end.timeIntervalSince(start) < Self.minimumSegmentDuration, s.segments.count > 1 {
            s.segments.remove(at: index)
        } else {
            s.segments[index].end = max(end, start)
        }
    }

    private func complete(_ s: inout SessionSnapshot, at endedAt: Date) {
        s.status = .completed
        let lastEnd = s.segments.compactMap(\.end).max() ?? s.startedAt
        s.endedAt = max(endedAt, lastEnd)
    }

    static func newSegment(side: Side, at now: Instant) -> Segment {
        Segment(side: side, start: now.wall, startMonotonic: now.monotonic, startBootID: now.bootID)
    }
}

extension SessionTransition {
    static func noOp(_ snapshot: SessionSnapshot) -> SessionTransition {
        SessionTransition(snapshot: snapshot, effects: [])
    }
}
