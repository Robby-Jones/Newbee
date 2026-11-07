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
