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
            if isRunning, let open = state.openSegment, open.start <= now.wall {
                closeOpenSegment(&next, at: now.wall)
                endedAt = now.wall
            } else if !isRunning, (state.segments.last?.end ?? state.startedAt) <= now.wall.addingTimeInterval(Self.futureTolerance) {
                // Paused: the feed really ended when the last segment closed.
                endedAt = state.segments.last?.end ?? state.startedAt
            } else {
                // Some stored times are later than now (the clock moved backwards): end at now and
                // drop what lies beyond it. Refused if the whole session is in the future.
                guard Self.endTimeRange(for: state, now: now.wall) != nil else { throw .invalidTime }
                if isRunning { closeOpenSegment(&next, at: now.wall) }
                truncate(&next, at: now.wall)
                endedAt = now.wall
            }
            complete(&next, at: endedAt)
            effects = [.persist, .endActivity, .rescheduleReminders]

        case .endAt(let date):
            guard let range = Self.endTimeRange(for: state, now: now.wall), range.contains(date) else {
                throw .invalidTime
            }
            if isRunning { closeOpenSegment(&next, at: date) }
            truncate(&next, at: date)
            complete(&next, at: date)
            // The parent picked the end time after the fact, so it's an estimate.
            if next.source == .timer { next.source = .recovered }
            effects = [.persist, .endActivity, .rescheduleReminders]

        case .shiftTimestamps(let offset):
            guard offset != 0 else { return .noOp(state) }
            next.startedAt = state.startedAt.addingTimeInterval(offset)
            for index in next.segments.indices {
                next.segments[index].start = next.segments[index].start.addingTimeInterval(offset)
                next.segments[index].end = next.segments[index].end?.addingTimeInterval(offset)
            }
            let latest = next.segments.flatMap { [$0.start, $0.end] }.compactMap { $0 }.max() ?? next.startedAt
            guard latest <= now.wall.addingTimeInterval(Self.futureTolerance) else { throw .invalidTime }
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

    /// Removes everything after `date`: segments that start later are dropped (the first is
    /// always kept) and the rest end no later than `date`.
    private func truncate(_ s: inout SessionSnapshot, at date: Date) {
        s.segments = s.segments.enumerated()
            .filter { $0.offset == 0 || $0.element.start < date }
            .map(\.element)
        for index in s.segments.indices {
            s.segments[index].start = min(s.segments[index].start, date)
            s.segments[index].end = min(s.segments[index].end ?? date, date)
        }
        s.startedAt = s.segments.first?.start ?? min(s.startedAt, date)
    }

    private func complete(_ s: inout SessionSnapshot, at endedAt: Date) {
        s.status = .completed
        let lastEnd = s.segments.compactMap(\.end).max() ?? s.startedAt
        s.endedAt = max(endedAt, lastEnd)
    }

    /// The end times `.endAt` accepts for `session` at `now`. Recovery UIs use it to bound their
    /// time pickers. Normally from the running segment's start (or the moment a paused session
    /// was paused) up to now. If the clock moved backwards and those times are in the future,
    /// from the latest stored time that isn't. `nil` when the whole session lies in the future.
    public static func endTimeRange(for session: SessionSnapshot, now: Date) -> ClosedRange<Date>? {
        let upper = now.addingTimeInterval(futureTolerance)
        let running = session.status == .active ? session.openSegment : nil
        let earliest = running?.start ?? session.segments.compactMap(\.end).max() ?? session.startedAt
        if earliest <= upper { return earliest...upper }
        let pastTimes = ([session.startedAt] + session.segments.flatMap { [$0.start, $0.end] })
            .compactMap { $0 }
            .filter { $0 <= now }
        guard let lower = pastTimes.max() else { return nil }
        return lower...upper
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
