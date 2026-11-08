import NewbeeKit
import NewbeeShared
import SwiftUI

/// App-only additions on top of the shared tokens in NewbeeShared (docs/UX_SPEC.md §2).
extension NBColor {
    /// Text and glyphs drawn on a filled side color. Dark in both modes: the side tints are light
    /// enough that white text would fall below WCAG AA.
    static let onSide = Color(light: 0x1B1B20, dark: 0x0F0F12)

    /// Pumping sessions: a soft rose, distinct from the side and bottle colors.
    static let pump = Color(light: 0xE58FAE, dark: 0xF0A8C2)

    /// Hairline border for cards in dark mode.
    static let hairline = Color.primary.opacity(0.08)
}

extension Side {
    /// "Left" / "Right", for labels and VoiceOver.
    var title: String {
        self == .left ? String(localized: "Left") : String(localized: "Right")
    }
}

enum NBLayout {
    /// The round L / R timer buttons are at most this wide (thumb zone, one-handed use).
    static let sideCircleMaxDiameter: CGFloat = 168
    /// Smallest allowed hit target.
    static let minHitTarget: CGFloat = 44
    /// Pause / End buttons on the timer screen.
    static let primaryControlHeight: CGFloat = 60
}

extension Animation {
    /// State changes (start, switch, pause). Callers check Reduce Motion.
    static var nbState: Animation { .snappy(duration: 0.3) }
}

/// Haptic feedback events (docs/UX_SPEC.md §2): light on start/switch/pause, success on end,
/// warning on a rejected action. Each event is unique so repeated events still fire.
struct FeedbackEvent: Equatable {
    enum Kind: Equatable { case light, success, warning }

    let kind: Kind
    let id = UUID()

    var sensoryFeedback: SensoryFeedback {
        switch kind {
        case .light: .impact(weight: .light)
        case .success: .success
        case .warning: .warning
        }
    }
}
