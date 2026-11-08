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

    /// Bottle volume in milliliters; zero for breastfeeds.
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
    /// Canonical amount in milliliters.
    public var amountML: Double
    /// The unit the parent typed it in, so it is shown back the same way.
    public var enteredUnit: VolumeUnit

    public init(contents: BottleContents, amountML: Double, enteredUnit: VolumeUnit = .milliliters) {
        self.contents = contents
        self.amountML = amountML
        self.enteredUnit = enteredUnit
    }
}

/// History filter: any combination of breastfeeds, bottles and pumping sessions.
///
/// `.all` is every kind. An empty filter shows nothing; the History menu never leaves it empty.
public struct FeedFilter: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let breast = FeedFilter(rawValue: 1 << 0)
    public static let bottle = FeedFilter(rawValue: 1 << 1)
    /// Pumping sessions. They aren't feeds, so no `FeedEntry` matches this kind.
    public static let pump = FeedFilter(rawValue: 1 << 2)
    public static let all: FeedFilter = [.breast, .bottle, .pump]

    /// Each single kind, in menu order.
    public static let kinds: [FeedFilter] = [.breast, .bottle, .pump]

    public var isAll: Bool { isSuperset(of: .all) }

    public func includes(_ entry: FeedEntry) -> Bool {
        switch entry.kind {
        case .breast: contains(.breast)
        case .bottle: contains(.bottle)
        case .pump, .combo: false
        }
    }

    /// Whether pumping sessions show under this filter.
    public var includesPumping: Bool {
        contains(.pump)
    }

    /// Turns one kind on or off, but never turns off the last kind left.
    public mutating func toggle(_ kind: FeedFilter) {
        if contains(kind) {
            let remaining = subtracting(kind)
            if !remaining.isEmpty { self = remaining }
        } else {
            formUnion(kind)
        }
    }
}
