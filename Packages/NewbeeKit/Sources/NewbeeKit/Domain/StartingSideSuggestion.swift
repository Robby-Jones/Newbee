import Foundation

/// Settings' "Suggested starting side": which breast the app offers first for the next feed
/// (the "Suggested" tag in the Timer, Home's "Next:", manual entries and the Live Activity tint).
///
/// The default alternates from the side the last breastfeed ended on, which is how the app
/// always worked, so nothing changes until the parent picks something else.
public struct StartingSideSuggestion: Sendable, Hashable {
    public enum Mode: String, CaseIterable, Sendable, Identifiable {
        /// The other side from the last breastfeed's starting or ending side (`switchFrom`).
        case alternate
        case alwaysLeft
        case alwaysRight

        public var id: String { rawValue }
    }

    /// Which side of the last breastfeed `alternate` switches from.
    public enum SwitchFrom: String, CaseIterable, Sendable, Identifiable {
        case ended
        case started

        public var id: String { rawValue }
    }

    public var mode: Mode
    /// Only used by `alternate`; kept while another mode is picked so switching back restores it.
    public var switchFrom: SwitchFrom

    public init(mode: Mode = .alternate, switchFrom: SwitchFrom = .ended) {
        self.mode = mode
        self.switchFrom = switchFrom
    }

    /// The side to offer after a breastfeed that started on `firstSide` and ended (or is
    /// running) on `lastSide`. With no breastfeed yet, `alternate` offers Left.
    public func suggestedSide(firstSide: Side?, lastSide: Side?) -> Side {
        switch mode {
        case .alwaysLeft:
            return .left
        case .alwaysRight:
            return .right
        case .alternate:
            let from = switchFrom == .started ? (firstSide ?? lastSide) : (lastSide ?? firstSide)
            return from?.opposite ?? .left
        }
    }

    /// The side to offer after `session` (the running one or the last finished one).
    public func suggestedSide(after session: SessionSnapshot?) -> Side {
        suggestedSide(firstSide: session?.startingSide, lastSide: session?.lastSide)
    }
}
