import Foundation
import Observation

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
    /// The app sets it at launch and when the parent picks another theme. Reading it is
    /// observed, so a view that draws a themed token redraws by itself when the theme changes,
    /// keeping its state and scroll position.
    public static var current: NBTheme {
        get { NBThemeStore.shared.theme }
        set { NBThemeStore.shared.theme = newValue }
    }
}

/// Holds `NBTheme.current`: observable for SwiftUI, and read from any thread (UIKit resolves
/// colors wherever it draws).
final class NBThemeStore: Observable, @unchecked Sendable {
    static let shared = NBThemeStore()

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var stored = NBTheme.standard

    var theme: NBTheme {
        get {
            registrar.access(self, keyPath: \.theme)
            return lock.withLock { stored }
        }
        set {
            guard newValue != lock.withLock({ stored }) else { return }
            registrar.withMutation(of: self, keyPath: \.theme) {
                lock.withLock { stored = newValue }
            }
        }
    }
}
