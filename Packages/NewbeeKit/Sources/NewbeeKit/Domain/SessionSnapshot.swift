import Foundation

/// One continuous stretch of feeding on one side. Pauses are gaps between segments.
public struct Segment: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var side: Side
    public var start: Date
    /// `nil` while the segment is still running.
    public var end: Date?
    /// Continuous (monotonic) clock reading at `start`, used to detect wall-clock changes within one boot.
    public var startMonotonic: Double?
    /// Identifier of the boot during which the segment started.
    public var startBootID: String?

    public init(
        id: UUID = UUID(),
        side: Side,
        start: Date,
        end: Date? = nil,
        startMonotonic: Double? = nil,
        startBootID: String? = nil
    ) {
        self.id = id
        self.side = side
        self.start = start
        self.end = end
        self.startMonotonic = startMonotonic
        self.startBootID = startBootID
    }

    public var isOpen: Bool { end == nil }

    /// Duration of this segment as of `now`. Never negative.
    public func duration(at now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

/// An immutable, persistence-independent view of a breastfeeding session.
///
/// All durations are derived from segment timestamps and the supplied `now`; nothing is counted.
/// This type is the contract between the session engine, persistence, the UI and the Live Activity.
public struct SessionSnapshot: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var status: SessionStatus
    /// Ordered by `start`, non-overlapping. At most one open segment, and only when `status == .active`.
    public var segments: [Segment]
    public var startedAt: Date
    public var endedAt: Date?
    /// Incremented on every accepted change; used to make Live Activity intents idempotent.
    public var revision: Int
    /// IANA time zone identifier where the session started.
    public var timeZoneID: String
    public var source: EntrySource
    public var needsReview: Bool
    public var notes: String
    /// When the parent last answered "Keep going" on the recovery sheet. Recovery doesn't ask
    /// again about data older than this. Metadata only: it doesn't change the feed.
    public var recoveryAcknowledgedAt: Date?

    public init(
        id: UUID = UUID(),
        status: SessionStatus,
        segments: [Segment],
        startedAt: Date,
        endedAt: Date? = nil,
        revision: Int = 0,
        timeZoneID: String = TimeZone.current.identifier,
        source: EntrySource = .timer,
        needsReview: Bool = false,
        notes: String = "",
        recoveryAcknowledgedAt: Date? = nil
    ) {
        self.id = id
        self.status = status
        self.segments = segments
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.revision = revision
        self.timeZoneID = timeZoneID
        self.source = source
        self.needsReview = needsReview
        self.notes = notes
        self.recoveryAcknowledgedAt = recoveryAcknowledgedAt
    }

    /// The running segment, if any.
    public var openSegment: Segment? { segments.last(where: \.isOpen) }

    /// The side of the first segment.
    public var startingSide: Side? { segments.first?.side }

    /// The side currently running, or the side used last if paused or completed.
    public var lastSide: Side? { openSegment?.side ?? segments.last?.side }

    /// Feeding time on one side as of `now` (pauses excluded).
    public func duration(on side: Side, at now: Date) -> TimeInterval {
        segments.lazy.filter { $0.side == side }.reduce(0) { $0 + $1.duration(at: now) }
    }

    /// Total feeding time as of `now`: the sum of all segment durations (pauses excluded).
    public func feedingDuration(at now: Date) -> TimeInterval {
        segments.reduce(0) { $0 + $1.duration(at: now) }
    }

    /// Wall-clock span from start to end (or `now`), pauses included.
    public func span(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    /// Accumulated time on `side` from closed segments only. Used by the Live Activity, which
    /// renders the open segment with a system-driven timer.
    public func closedDuration(on side: Side) -> TimeInterval {
        segments.lazy.filter { $0.side == side && !$0.isOpen }.reduce(0) { $0 + $1.duration(at: $1.start) }
    }
}
