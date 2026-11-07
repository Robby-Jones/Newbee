# Theme

> Project: Newbee — native iOS 17+ app (SwiftUI, SwiftData, ActivityKit). NOT a web app: no React/Tailwind/CSS. Designs are iPhone screens (390×844 pt) and Live Activity surfaces. UI uses SF Pro / SF Pro Rounded, SF Symbols, system materials.

## Part 1 — Token summary

**Colors** (light / dark):
- canvas `#FAF8F5` / `#0F0F12` (app background)
- card `#FFFFFF` / `#1B1B20`
- accent (soft indigo) `#6B6FD6` / `#8E91F0` — primary actions, tint
- side.left (lavender) `#9C8CE0` / `#B3A6F0`
- side.right (teal) `#4FB3A9` / `#6FCFC4`
- bottle.breastMilk (peach) `#F2A37B` / `#F5B593`
- bottle.formula (butter) `#E8C25A` / `#EDD07A`
- destructive (muted rose) `#D9667A` / `#E88092`
- onSide text `#1B1B20` / `#0F0F12`; hairline = primary @ 8%
- Text: iOS system label / secondaryLabel / tertiaryLabel
- Dynamic Island is always black; Live Activity Lock Screen uses the system translucent background.

**Type**: SF Pro (body, semantic text styles: largeTitle, title2, title3, headline, subheadline, footnote, caption); SF Pro Rounded for numerals and headings; timer numerals `.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit()`.

**Spacing** (4-pt grid): xs 4 · s 8 · m 12 · l 16 · xl 24.
**Radius**: card 20 (continuous) · control 16.
**Shadow**: light mode cards `y:2 blur:4 black @ 6%`; dark mode 1-pt hairline border, no shadow.
**Sizes**: min hit target 44 · side buttons ≥160 tall · primary controls 60 tall.
**Motion**: `.snappy(0.3)` springs, numeric text transitions; Reduce Motion respected.

## Part 2 — Raw sources

### `Packages/NewbeeShared/Sources/NewbeeShared/DesignTokens/DesignTokens.swift`

```swift
#if canImport(SwiftUI) && canImport(UIKit)
import NewbeeKit
import SwiftUI
import UIKit

/// Design tokens shared by the app and the Live Activity so both look like one product.
/// Values are the draft palette from docs/UX_SPEC.md §2 and are refined in Phase 3.
public enum NBColor {
    public static let canvas = Color(light: 0xFAF8F5, dark: 0x0F0F12)
    public static let card = Color(light: 0xFFFFFF, dark: 0x1B1B20)
    public static let accent = Color(light: 0x6B6FD6, dark: 0x8E91F0)
    public static let left = Color(light: 0x9C8CE0, dark: 0xB3A6F0)
    public static let right = Color(light: 0x4FB3A9, dark: 0x6FCFC4)
    public static let bottleBreastMilk = Color(light: 0xF2A37B, dark: 0xF5B593)
    public static let bottleFormula = Color(light: 0xE8C25A, dark: 0xEDD07A)
    public static let destructive = Color(light: 0xD9667A, dark: 0xE88092)

    public static func side(_ side: Side) -> Color {
        side == .left ? left : right
    }
}

public enum NBSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

public enum NBRadius {
    public static let card: CGFloat = 20
    public static let control: CGFloat = 16
}

public enum NBFont {
    /// Large timer numerals: rounded, monospaced digits so they don't jitter.
    public static func timer(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

extension Color {
    /// A color that adapts to light and dark mode, from 0xRRGGBB values.
    public init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
```

### `Newbee/Shared/DesignSystem/AppDesignSystem.swift`

```swift
import NewbeeKit
import NewbeeShared
import SwiftUI

/// App-only additions on top of the shared tokens in NewbeeShared (docs/UX_SPEC.md §2).
extension NBColor {
    /// Text and glyphs drawn on a filled side color. Dark in both modes: the side tints are light
    /// enough that white text would fall below WCAG AA.
    static let onSide = Color(light: 0x1B1B20, dark: 0x0F0F12)

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
    /// Primary timer controls are at least this tall (thumb zone, one-handed use).
    static let sideButtonMinHeight: CGFloat = 160
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
```
