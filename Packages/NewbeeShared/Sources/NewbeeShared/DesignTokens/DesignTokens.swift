#if canImport(SwiftUI) && canImport(UIKit)
import NewbeeKit
import SwiftUI
import UIKit

/// Design tokens shared by the app and the Live Activity so both look like one product.
/// Values started as the draft palette from docs/UX_SPEC.md §2.
///
/// Contrast rules (WCAG AA): the side, bottle and pump colors are soft pastels meant for fills,
/// chart marks and borders. Text or glyphs drawn on them use `onSide`. When a feature color is
/// itself the text or icon color, use its `…Ink` variant: the same hue, darkened in light mode to
/// reach at least 4.5:1 on the canvas, the card and a light tint of itself. In dark mode each ink
/// equals its fill, which already passes there.
public enum NBColor {
    public static let canvas = Color(light: 0xFAF8F5, dark: 0x0F0F12)
    public static let card = Color(light: 0xFFFFFF, dark: 0x1B1B20)
    /// Used as text, as a button fill under white text and as a tint, so it passes AA as is.
    public static let accent = Color(light: 0x5054C2, dark: 0x8E91F0)
    public static let left = Color(light: 0x9C8CE0, dark: 0xB3A6F0)
    public static let right = Color(light: 0x4FB3A9, dark: 0x6FCFC4)
    public static let bottleBreastMilk = Color(light: 0xF2A37B, dark: 0xF5B593)
    public static let bottleFormula = Color(light: 0xE8C25A, dark: 0xEDD07A)
    /// Used as text and as a button fill under white text, so it passes AA as is.
    public static let destructive = Color(light: 0xAE2F4B, dark: 0xE88092)

    public static let leftInk = Color(light: 0x6A58C4, dark: 0xB3A6F0)
    public static let rightInk = Color(light: 0x26706A, dark: 0x6FCFC4)
    public static let bottleBreastMilkInk = Color(light: 0xA9522A, dark: 0xF5B593)
    public static let bottleFormulaInk = Color(light: 0x846510, dark: 0xEDD07A)

    /// Secondary text. The system `.secondary` is about 3.3:1 on the light canvas, below AA.
    public static let secondaryText = Color(light: 0x66666C, dark: 0xA1A1AA)

    public static func side(_ side: Side) -> Color {
        side == .left ? left : right
    }

    public static func sideInk(_ side: Side) -> Color {
        side == .left ? leftInk : rightInk
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
