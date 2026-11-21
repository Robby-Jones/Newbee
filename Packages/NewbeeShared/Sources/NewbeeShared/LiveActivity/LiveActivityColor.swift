import Foundation

/// Settings → Appearance → Live Activity (docs/UX_SPEC.md §2.1): the Live Activity's colors,
/// picked apart from the app's color theme.
///
/// One choice colors the whole Lock Screen card (background, text and the round "+") and the "+"
/// and Pause in the Dynamic Island, whose background iOS keeps black. `matchTheme` is the default
/// and follows the app theme as before: black for Indigo, a light card for the other themes.
/// Kept on this phone only, like the theme.
public enum LiveActivityColor: Hashable, Sendable {
    /// Follows the app's color theme (`card(for:)`).
    case matchTheme
    /// Black card, white text.
    case black
    /// A soft light card in a theme's color, with dark text.
    case light(NBTheme)
    /// A deep card in a theme's color, with white text.
    case dark(NBTheme)

    /// The card this choice draws with the app in `theme`: never `matchTheme`.
    public func card(for theme: NBTheme) -> LiveActivityColor {
        guard self == .matchTheme else { return self }
        return Self.matching(theme)
    }

    /// The card that matches a theme: black for the standard (Indigo) theme, as it always was,
    /// otherwise the theme's light card.
    public static func matching(_ theme: NBTheme) -> LiveActivityColor {
        theme == .standard ? .black : .light(theme)
    }

    /// Every card a parent can pick, after "Match app theme".
    public static let lightCards: [LiveActivityColor] = NBTheme.allCases.map(LiveActivityColor.light)
    public static let darkCards: [LiveActivityColor] = NBTheme.allCases.map(LiveActivityColor.dark)

    /// The theme a light or dark card is tinted with; `nil` for black and Match.
    public var tint: NBTheme? {
        switch self {
        case .matchTheme, .black: nil
        case .light(let theme), .dark(let theme): theme
        }
    }

    /// Whether the card is light, so its text is dark.
    public var isLight: Bool {
        if case .light = self { true } else { false }
    }
}

extension LiveActivityColor: RawRepresentable, Codable {
    /// "match", "black", "light.pink", "dark.sage"…: stored in Settings and sent in the Live
    /// Activity's content.
    public var rawValue: String {
        switch self {
        case .matchTheme: "match"
        case .black: "black"
        case .light(let theme): "light.\(theme.rawValue)"
        case .dark(let theme): "dark.\(theme.rawValue)"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "match": self = .matchTheme
        case "black": self = .black
        default:
            let parts = rawValue.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2, let theme = NBTheme(rawValue: parts[1]) else { return nil }
            switch parts[0] {
            case "light": self = .light(theme)
            case "dark": self = .dark(theme)
            default: return nil
            }
        }
    }

    /// An unknown value (from a newer build) reads as Match rather than failing the whole content.
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = LiveActivityColor(rawValue: value) ?? .matchTheme
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
