import NewbeeKit
import NewbeeShared
import SwiftUI

/// A side's letter in its tint. Color is never the only signal, so the letter is always shown.
struct SideBadge: View {
    enum Style {
        /// Solid side tint with dark letter.
        case filled
        /// Light tint wash with tinted letter, for neutral backgrounds.
        case soft
        /// For use on top of a filled side-tinted surface.
        case onTint
    }

    let side: Side
    var style: Style = .filled
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 28

    var body: some View {
        Text(side.shortLabel)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .accessibilityElement()
            .accessibilityLabel(side.title)
    }

    private var foreground: Color {
        switch style {
        case .filled, .onTint: NBColor.onSide
        case .soft: NBColor.side(side)
        }
    }

    private var fill: Color {
        switch style {
        case .filled: NBColor.side(side)
        case .soft: NBColor.side(side).opacity(0.18)
        case .onTint: NBColor.onSide.opacity(0.12)
        }
    }
}

/// A small "live" dot. Pulses while a session runs, static under Reduce Motion.
struct LiveDot: View {
    var color: Color
    var isLive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8))
            .foregroundStyle(color)
            .symbolEffect(.pulse, options: .repeating, isActive: isLive && !reduceMotion)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        SideBadge(side: .left)
        SideBadge(side: .right)
        SideBadge(side: .left, style: .soft)
        SideBadge(side: .right, style: .soft)
        LiveDot(color: NBColor.left)
    }
    .padding()
}
