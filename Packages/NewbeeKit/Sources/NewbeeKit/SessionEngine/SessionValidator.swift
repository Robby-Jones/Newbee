import Foundation

/// A broken rule in a breastfeeding session (docs/DATA_MODEL.md §3).
public enum SessionInvariantViolation: Error, Sendable, Hashable {
    case noSegments
    case multipleOpenSegments
    /// An open segment exists but the session is not active, or it is not the last segment.
    case misplacedOpenSegment
    /// The session is active but nothing is running.
    case activeWithoutOpenSegment
    case segmentEndsBeforeStart(UUID)
    /// Segments are out of order or overlap.
    case segmentsOverlap(UUID, UUID)
    /// `startedAt` differs from the first segment's start.
    case startMismatch
    case completedWithoutEnd
    case endBeforeLastSegment
    case endWhileOpen
    /// A timestamp is later than now (beyond a small tolerance).
    case inFuture
}

/// Checks the invariants the engine maintains. Used when saving manual edits so that edited
/// sessions obey exactly the same rules as timed ones.
public enum SessionValidator {
    public static func violations(
        in s: SessionSnapshot,
        now: Date,
        futureTolerance: TimeInterval = SessionEngine.futureTolerance
    ) -> [SessionInvariantViolation] {
        var found: [SessionInvariantViolation] = []
        guard let first = s.segments.first else { return [.noSegments] }

        let openCount = s.segments.filter(\.isOpen).count
        if openCount > 1 { found.append(.multipleOpenSegments) }
        if openCount == 1, s.status != .active || !(s.segments.last?.isOpen ?? false) {
            found.append(.misplacedOpenSegment)
        }
        if s.status == .active, openCount == 0 { found.append(.activeWithoutOpenSegment) }

        for segment in s.segments {
            if let end = segment.end, end < segment.start { found.append(.segmentEndsBeforeStart(segment.id)) }
        }
        for (a, b) in zip(s.segments, s.segments.dropFirst()) {
            if let aEnd = a.end, b.start >= aEnd, b.start >= a.start { continue }
            found.append(.segmentsOverlap(a.id, b.id))
        }

        if s.startedAt != first.start { found.append(.startMismatch) }

        switch s.status {
        case .completed:
            if let endedAt = s.endedAt {
                if let lastEnd = s.segments.compactMap(\.end).max(), endedAt < lastEnd {
                    found.append(.endBeforeLastSegment)
                }
            } else {
                found.append(.completedWithoutEnd)
            }
        case .active, .paused:
            if s.endedAt != nil { found.append(.endWhileOpen) }
        }

        let latest = ([s.startedAt, s.endedAt] + s.segments.flatMap { [$0.start, $0.end] }).compactMap { $0 }.max()
        if let latest, latest > now.addingTimeInterval(futureTolerance) { found.append(.inFuture) }

        return found
    }

    public static func isValid(_ s: SessionSnapshot, now: Date) -> Bool {
        violations(in: s, now: now).isEmpty
    }
}
