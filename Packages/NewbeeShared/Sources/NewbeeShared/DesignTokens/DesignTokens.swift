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
///
/// The canvas, the card and the accent follow the color theme (`NBTheme.colors`). Every other
/// token is the same in every theme.
public enum NBColor {
    // Computed, not stored: each read picks up the current theme, and SwiftUI redraws the views
    // that read them when it changes (`NBTheme.current` is observed).
    public static var canvas: Color { Color(themed: { $0.canvas }) }
    public static var card: Color { Color(themed: { $0.card }) }
    /// Used as text, as a button fill under white text and as a tint, so it passes AA as is in
    /// every theme (at least 4.9:1 on the canvas).
    public static var accent: Color { Color(themed: { $0.accent }) }
    /// Breastfeeds in charts (`NBThemeColors.chartBreast`).
    public static var chartBreast: Color { Color(themed: { $0.chartBreast }) }
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

/// A 0xRRGGBB color for light mode and one for dark mode.
public struct NBColorPair: Sendable {
    public let light: UInt32
    public let dark: UInt32

    public init(_ light: UInt32, _ dark: UInt32) {
        self.light = light
        self.dark = dark
    }
}

/// The tokens a color theme changes (docs/UX_SPEC.md §2.1). Light accents reach at least 4.9:1
/// on their canvas and white; dark accents at least 7.8:1 on their dark card.
public struct NBThemeColors: Sendable {
    public let canvas: NBColorPair
    public let card: NBColorPair
    public let accent: NBColorPair
    /// Breastfeeds in charts, next to the peach bottle color. The accent, except in themes whose
    /// accent is too close to the bottle color to tell apart.
    public let chartBreast: NBColorPair

    init(canvas: NBColorPair, card: NBColorPair, accent: NBColorPair, chartBreast: NBColorPair? = nil) {
        self.canvas = canvas
        self.card = card
        self.accent = accent
        self.chartBreast = chartBreast ?? accent
    }
}

extension NBTheme {
    public var colors: NBThemeColors {
        switch self {
        case .standard:
            NBThemeColors(canvas: NBColorPair(0xFAF8F5, 0x0F0F12), card: NBColorPair(0xFFFFFF, 0x1B1B20), accent: NBColorPair(0x5054C2, 0x8E91F0))
        case .pink:
            NBThemeColors(canvas: NBColorPair(0xFDF4F7, 0x130E11), card: NBColorPair(0xFFFFFF, 0x211A1E), accent: NBColorPair(0xA8336A, 0xE97DAE))
        case .sage:
            NBThemeColors(canvas: NBColorPair(0xF5F8F4, 0x0E120F), card: NBColorPair(0xFFFFFF, 0x1A1F1B), accent: NBColorPair(0x4A7553, 0x8FC29A))
        case .ocean:
            NBThemeColors(canvas: NBColorPair(0xF4F7FA, 0x0D1115), card: NBColorPair(0xFFFFFF, 0x191E24), accent: NBColorPair(0x2F6690, 0x7FB8E6))
        case .lavender:
            NBThemeColors(canvas: NBColorPair(0xF7F5FB, 0x110F15), card: NBColorPair(0xFFFFFF, 0x1D1A23), accent: NBColorPair(0x6B4FB0, 0xB9A3F0))
        case .peach:
            NBThemeColors(canvas: NBColorPair(0xFCF6F2, 0x14100D), card: NBColorPair(0xFFFFFF, 0x221B17), accent: NBColorPair(0x9E4A1C, 0xF3A77E),
                          // The peach accent looks like the bottle color in a chart: a deep terracotta instead.
                          chartBreast: NBColorPair(0x9E4A1C, 0xB5532A))
        }
    }
}

extension Color {
    /// A color that adapts to light and dark mode, in the current color theme (`NBTheme.current`).
    /// The theme is read here, when the view draws, so the view redraws when it changes.
    public init(themed pick: (NBThemeColors) -> NBColorPair) {
        let pair = pick(NBTheme.current.colors)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
    }

    /// A fixed 0xRRGGBB color, the same in light and dark mode.
    public init(rgb: UInt32) {
        self.init(uiColor: UIColor(rgb: rgb))
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
