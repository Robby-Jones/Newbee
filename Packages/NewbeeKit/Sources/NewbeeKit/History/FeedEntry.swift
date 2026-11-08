import Foundation

/// A finished feed of any kind, as History and the dashboard show it.
///
/// A persistence-independent value: the app maps each completed `FeedingSession` to one of these,
/// and every summary below is computed from them, so the logic is testable on Linux.
public struct FeedEntry: Sendable, Hashable, Identifiable {
    public enum Details: Sendable, Hashable {
        /// Per-side feeding time (pauses excluded) and the sides used first and last.
        case breast(left: TimeInterval, right: TimeInterval, firstSide: Side?, lastSide: Side?)
        case bottle(BottleSummary)
    }

    public var id: UUID
    /// When the feed started. Feeding intervals are measured start to start.
    public var start: Date
    public var end: Date?
    public var details: Details
    public var notes: String
    public var needsReview: Bool
    public var source: EntrySource

    public init(
        id: UUID,
        start: Date,
        end: Date?,
        details: Details,
        notes: String = "",
        needsReview: Bool = false,
        source: EntrySource = .timer
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.details = details
        self.notes = notes
        self.needsReview = needsReview
        self.source = source
    }

    /// A finished breastfeeding session. Durations are derived from its segment timestamps.
    public init(breast session: SessionSnapshot) {
        let end = session.endedAt ?? session.segments.compactMap(\.end).max() ?? session.startedAt
        self.init(
            id: session.id,
            start: session.startedAt,
            end: end,
            details: .breast(
                left: session.duration(on: .left, at: end),
                right: session.duration(on: .right, at: end),
                firstSide: session.startingSide,
                lastSide: session.lastSide
            ),
            notes: session.notes,
            needsReview: session.needsReview,
            source: session.source
        )
    }

    public var kind: FeedingKind {
        switch details {
        case .breast: .breast
        case .bottle: .bottle
        }
    }

    /// Breastfeeding time on both sides; zero for bottles.
    public var breastDuration: TimeInterval {
        if case let .breast(left, right, _, _) = details { return left + right }
        return 0
    }

    /// Bottle volume in millilitres; zero for breastfeeds.
    public var bottleML: Double {
        if case let .bottle(bottle) = details { return bottle.amountML }
        return 0
    }

    /// The breast side used last, for suggesting the next side. `nil` for bottles.
    public var lastSide: Side? {
        if case let .breast(_, _, _, last) = details { return last }
        return nil
    }
}

/// What a bottle feed recorded.
public struct BottleSummary: Sendable, Hashable {
    public var contents: BottleContents
    /// Canonical amount in millilitres.
    public var amountML: Double
    /// The unit the parent typed it in, so it is shown back the same way.
    public var enteredUnit: VolumeUnit

    public init(contents: BottleContents, amountML: Double, enteredUnit: VolumeUnit = .milliliters) {
        self.contents = contents
        self.amountML = amountML
        self.enteredUnit = enteredUnit
    }
}

/// History filter: All · Breast · Bottle · Pumping.
public enum FeedFilter: String, Sendable, CaseIterable, Hashable {
    case all
    case breast
    case bottle
    /// Pumping sessions only. They aren't feeds, so no `FeedEntry` matches.
    case pump

    public func includes(_ entry: FeedEntry) -> Bool {
        switch self {
        case .all: true
        case .breast: entry.kind == .breast
        case .bottle: entry.kind == .bottle
        case .pump: false
        }
    }

    /// Whether pumping sessions show under this filter.
    public var includesPumping: Bool {
        self == .all || self == .pump
    }
}
