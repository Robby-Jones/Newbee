import Foundation

/// Thresholds for launch and foreground recovery (docs/TIMER_ENGINE.md §5).
public struct RecoveryPolicy: Sendable, Hashable {
    /// A segment running (or a pause lasting) longer than this triggers "Were you still feeding?".
    /// Parent-configurable; default 45 min.
    public var stillFeedingThreshold: TimeInterval
    /// The prompt always appears beyond this, whatever the configured threshold.
    public var hardLimit: TimeInterval
    /// Disagreement between wall and monotonic elapsed time that counts as a clock change.
    public var clockChangeTolerance: TimeInterval
    /// Used to suggest an end time when there's no feeding history yet.
    public var defaultSegmentEstimate: TimeInterval

    public init(
        stillFeedingThreshold: TimeInterval = 45 * 60,
        hardLimit: TimeInterval = 3 * 60 * 60,
        clockChangeTolerance: TimeInterval = 60,
        defaultSegmentEstimate: TimeInterval = 15 * 60
    ) {
        self.stillFeedingThreshold = stillFeedingThreshold
        self.hardLimit = hardLimit
        self.clockChangeTolerance = clockChangeTolerance
        self.defaultSegmentEstimate = defaultSegmentEstimate
    }

    public var effectiveThreshold: TimeInterval { min(stillFeedingThreshold, hardLimit) }
}

/// What the recovery sheet asks the parent about. Recovery never discards data on its own.
public struct RecoveryPrompt: Identifiable, Hashable, Sendable {
    public enum Reason: String, Hashable, Sendable {
        /// The timer has been running (or paused) for a long time: "Were you still feeding?"
        case longRunning
        /// The device clock changed during this boot; `correctedStart` holds the start time
        /// measured by the continuous clock.
        case clockChanged
        /// A recorded time is in the future (the clock moved backwards, or a reboot hid a change).
        case futureStart
    }

    public var session: SessionSnapshot
    public var reason: Reason
    /// A plausible end, pre-filled in "End at …": the running segment's start plus a typical
    /// segment length (never later than now), or the moment a paused session was paused.
    public var suggestedEnd: Date
    /// For `.clockChanged`: what the running segment's start should be.
    public var correctedStart: Date?

    public var id: UUID { session.id }

    public init(session: SessionSnapshot, reason: Reason, suggestedEnd: Date, correctedStart: Date? = nil) {
        self.session = session
        self.reason = reason
        self.suggestedEnd = suggestedEnd
        self.correctedStart = correctedStart
    }
}

/// The outcome of reconciling stored open sessions with the current time.
public struct RecoveryPlan: Sendable, Hashable {
    /// The one session that stays active or paused, as it should be stored.
    public var survivor: SessionSnapshot?
    /// Sessions that must be saved before anything else (closed duplicates, review flags).
    public var updates: [SessionSnapshot]
    /// A question for the parent, if any.
    public var prompt: RecoveryPrompt?
}

/// Pure launch/foreground reconciliation. The `RecoveryCoordinator` persists and presents the result.
public struct RecoveryPlanner: Sendable {
    public var policy: RecoveryPolicy

    public init(policy: RecoveryPolicy = RecoveryPolicy()) {
        self.policy = policy
    }

    /// - Parameters:
    ///   - openSessions: every stored session whose status is active or paused, in any order.
    ///   - typicalSegmentDuration: median segment length for this baby, if known.
    ///   - acknowledged: session ID → the moment the parent last answered "Keep going".
    ///     Issues about data older than that are not raised again, and "still feeding?" restarts
    ///     its count from that moment.
    public func plan(
        openSessions: [SessionSnapshot],
        at now: Instant,
        typicalSegmentDuration: TimeInterval? = nil,
        acknowledged: [UUID: Date] = [:]
    ) -> RecoveryPlan {
        let open = openSessions
            .filter { $0.status != .completed }
            .sorted { ($0.startedAt, $0.revision) > ($1.startedAt, $1.revision) }
        guard var survivor = open.first else { return RecoveryPlan(survivor: nil, updates: [], prompt: nil) }

        // Duplicates should be impossible; close them defensively at the moment the newer feed began.
        var updates = open.dropFirst().map { closeDuplicate($0, supersededAt: survivor.startedAt, now: now.wall) }

        let ack = acknowledged[survivor.id]
        var prompt: RecoveryPrompt?
        if let issue = clockIssue(in: survivor, now: now, acknowledgedAt: ack) {
            prompt = issue
            if !survivor.needsReview {
                survivor.needsReview = true
                survivor.revision += 1
                updates.append(survivor)
            }
        } else {
            prompt = longRunningPrompt(for: survivor, now: now.wall, typical: typicalSegmentDuration, acknowledgedAt: ack)
        }
        prompt?.session = survivor
        return RecoveryPlan(survivor: survivor, updates: updates, prompt: prompt)
    }

    /// Median length of closed segments in recent sessions; feeds the suggested end time.
    public static func typicalSegmentDuration(from sessions: [SessionSnapshot]) -> TimeInterval? {
        let durations = sessions
            .flatMap(\.segments)
            .compactMap { s in s.end.map { $0.timeIntervalSince(s.start) } }
            .filter { $0 >= 60 }
            .sorted()
        guard !durations.isEmpty else { return nil }
        let mid = durations.count / 2
        return durations.count.isMultiple(of: 2) ? (durations[mid - 1] + durations[mid]) / 2 : durations[mid]
    }

    // MARK: - Checks

    private func closeDuplicate(_ s: SessionSnapshot, supersededAt: Date, now: Date) -> SessionSnapshot {
        var closed = s
        if let index = closed.segments.lastIndex(where: \.isOpen) {
            let start = closed.segments[index].start
            closed.segments[index].end = max(start, min(supersededAt, now))
        }
        let lastEnd = closed.segments.compactMap(\.end).max() ?? closed.startedAt
        closed.status = .completed
        closed.endedAt = max(lastEnd, closed.startedAt)
        closed.needsReview = true
        closed.source = .recovered
        closed.revision += 1
        return closed
    }

    private func clockIssue(in s: SessionSnapshot, now: Instant, acknowledgedAt: Date?) -> RecoveryPrompt? {
        if let open = s.status == .active ? s.openSegment : nil {
            if let ack = acknowledgedAt, open.start <= ack { return nil }
            // Same boot: the continuous clock is trustworthy, so it reveals wall-clock changes.
            if let bootID = now.bootID, open.startBootID == bootID,
               let monoNow = now.monotonic, let monoStart = open.startMonotonic {
                let monotonicElapsed = monoNow - monoStart
                let wallElapsed = now.wall.timeIntervalSince(open.start)
                if monotonicElapsed >= 0, abs(wallElapsed - monotonicElapsed) > policy.clockChangeTolerance {
                    let corrected = now.wall.addingTimeInterval(-monotonicElapsed)
                    return RecoveryPrompt(
                        session: s,
                        reason: .clockChanged,
                        suggestedEnd: now.wall,
                        correctedStart: corrected
                    )
                }
            }
            if open.start > now.wall.addingTimeInterval(policy.clockChangeTolerance) {
                return RecoveryPrompt(session: s, reason: .futureStart, suggestedEnd: open.start)
            }
            return nil
        }
        let latest = s.segments.compactMap(\.end).max() ?? s.startedAt
        if let ack = acknowledgedAt, latest <= ack { return nil }
        if latest > now.wall.addingTimeInterval(policy.clockChangeTolerance) {
            return RecoveryPrompt(session: s, reason: .futureStart, suggestedEnd: latest)
        }
        return nil
    }

    private func longRunningPrompt(
        for s: SessionSnapshot,
        now: Date,
        typical: TimeInterval?,
        acknowledgedAt: Date?
    ) -> RecoveryPrompt? {
        let since: Date
        let suggestedEnd: Date
        if s.status == .active, let open = s.openSegment {
            since = open.start
            let estimate = typical ?? policy.defaultSegmentEstimate
            suggestedEnd = min(now, open.start.addingTimeInterval(estimate))
        } else {
            // Paused and forgotten: the feed really ended when it was paused.
            since = s.segments.compactMap(\.end).max() ?? s.startedAt
            suggestedEnd = since
        }
        let countFrom = max(since, acknowledgedAt ?? .distantPast)
        guard now.timeIntervalSince(countFrom) > policy.effectiveThreshold else { return nil }
        return RecoveryPrompt(session: s, reason: .longRunning, suggestedEnd: suggestedEnd)
    }
}
