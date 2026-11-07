import Foundation

/// The Edit sheet's "simple mode" for a finished breastfeed (docs/UX_SPEC.md §3.7): a start time,
/// the side used first, and time on each side. It becomes back-to-back segments, first side first.
///
/// Durations are kept exactly (not rounded to minutes), so opening and saving an untouched
/// draft reproduces the original session.
public struct SimpleBreastEdit: Sendable, Hashable {
    public var start: Date
    public var firstSide: Side
    public var left: TimeInterval
    public var right: TimeInterval

    public init(start: Date, firstSide: Side, left: TimeInterval, right: TimeInterval) {
        self.start = start
        self.firstSide = firstSide
        self.left = left
        self.right = right
    }

    /// A blank manual entry: `left`/`right` minutes ending at `now`.
    public static func manualEntry(endingAt now: Date, firstSide: Side, left: TimeInterval = 10 * 60, right: TimeInterval = 10 * 60) -> SimpleBreastEdit {
        SimpleBreastEdit(start: now.addingTimeInterval(-(left + right)), firstSide: firstSide, left: left, right: right)
    }

    /// The simple form of `session`, or `nil` when it can't be shown that way without losing
    /// information: more than one segment per side, or a pause between the two sides.
    public init?(_ session: SessionSnapshot) {
        guard session.status == .completed, let first = session.segments.first,
              session.segments.allSatisfy({ $0.end != nil }) else { return nil }
        switch session.segments.count {
        case 1:
            break
        case 2:
            let second = session.segments[1]
            guard second.side != first.side, second.start == first.end else { return nil }
        default:
            return nil
        }
        let end = session.segments.last?.end ?? first.start
        self.init(
            start: first.start,
            firstSide: first.side,
            left: session.duration(on: .left, at: end),
            right: session.duration(on: .right, at: end)
        )
    }

    public var total: TimeInterval { max(0, left) + max(0, right) }
    public var end: Date { start.addingTimeInterval(total) }

    /// Builds the edited session from `base` (keeping its ID, notes and metadata and reusing
    /// segment IDs where it can). A side with zero time gets no segment.
    public func apply(to base: SessionSnapshot) -> SessionSnapshot {
        var result = base
        let order = [firstSide, firstSide.opposite]
        var cursor = start
        var segments: [Segment] = []
        for side in order {
            let length = max(0, side == .left ? left : right)
            guard length > 0 else { continue }
            let reusedID = base.segments.first(where: { $0.side == side })?.id ?? UUID()
            segments.append(Segment(id: reusedID, side: side, start: cursor, end: cursor.addingTimeInterval(length)))
            cursor = cursor.addingTimeInterval(length)
        }
        result.segments = segments
        result.startedAt = segments.first?.start ?? start
        result.endedAt = segments.last?.end ?? start
        result.status = .completed
        return result
    }

    /// A new completed manual session.
    public func newSession(notes: String = "", timeZoneID: String = TimeZone.current.identifier) -> SessionSnapshot {
        let base = SessionSnapshot(status: .completed, segments: [], startedAt: start, timeZoneID: timeZoneID, source: .manual, notes: notes)
        return apply(to: base)
    }
}

/// Helpers for the Edit sheet's "segments mode".
public enum SessionEditing {
    /// Puts an edited completed session in canonical shape: segments sorted by start,
    /// `startedAt` = first segment's start, `endedAt` = last segment's end.
    /// What's left (overlaps, end before start, future times) is reported by `SessionValidator`.
    public static func normalizedCompleted(_ session: SessionSnapshot) -> SessionSnapshot {
        var result = session
        result.segments.sort { ($0.start, $0.end ?? .distantFuture) < ($1.start, $1.end ?? .distantFuture) }
        if let first = result.segments.first {
            result.startedAt = first.start
        }
        result.endedAt = result.segments.compactMap(\.end).max() ?? result.startedAt
        result.status = .completed
        return result
    }

    /// A new segment to append in segments mode: the opposite side, starting where the last one ended.
    public static func nextSegment(after session: SessionSnapshot, length: TimeInterval = 5 * 60) -> Segment {
        let last = session.segments.last
        let start = last?.end ?? session.startedAt
        return Segment(side: last?.side.opposite ?? .left, start: start, end: start.addingTimeInterval(length))
    }
}
