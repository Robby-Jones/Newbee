import Foundation

/// The app's color theme, picked in Settings → Appearance (docs/UX_SPEC.md §2.1).
///
/// Only the accent, the canvas and the card change with the theme, plus the Lock Screen Live
/// Activity's card (black in the standard theme, a soft tint of the theme's color otherwise) and,
/// if the parent picks it, the app icon's background. The side, bottle and pump colors stay the
/// same in every theme so feed types read the same way. The theme is kept per device, not synced,
/// so each parent can pick their own.
///
/// The Live Activity gets the theme through its content (`ContentState.theme`), so a change
/// redraws it with the next update.
public enum NBTheme: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    /// Indigo accent on a warm cream canvas: Newbee's original look.
    case standard
    /// Soft rose accent on a faint blush canvas, with a blush Lock Screen Live Activity.
    case pink
    /// Deep sage green on a faint green-gray canvas.
    case sage
    /// Deep ocean blue on a faint blue-gray canvas.
    case ocean
    /// Deep violet on a faint lilac canvas.
    case lavender
    /// Burnt orange on a faint peach canvas.
    case peach

    public var id: String { rawValue }

    /// The theme the app's design tokens resolve against (`NBColor.accent`, `canvas`, `card`).
    /// The app sets it at launch and when the parent picks another theme.
    public static var current: NBTheme {
        get { storage.value }
        set { storage.value = newValue }
    }

    private static let storage = Locked(NBTheme.standard)
}

/// A value read from any thread: UIKit resolves colors wherever it draws.
private final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
