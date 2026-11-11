import NewbeeKit
import NewbeeShared
import SwiftUI

/// One of the two big round LEFT / RIGHT controls on the timer screen (docs/UX_SPEC.md §3.3),
/// with the side's time inside. Up to 168 pt across, so it can be hit with a thumb in the dark.
struct SideButton: View {
    enum Mode: Equatable {
        /// No session yet. The suggested side is pre-tinted and tagged.
        case start(suggested: Bool)
        /// This side is running; tapping pauses.
        case active
        /// The other side is running; tapping switches here.
        case switchTo
        /// The session is paused; tapping resumes on this side.
        case resumeHere(wasLast: Bool)
    }

    let side: Side
    let mode: Mode
    /// Time on this side so far; `nil` before the session starts.
    let elapsed: TimeInterval?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: NBSpacing.xs) {
                Text(side.shortLabel)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                if let elapsed {
                    TimerText(elapsed, size: 34, relativeTo: .title)
                } else {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .padding(.vertical, NBSpacing.xs)
                }
                caption
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isFilled ? NBColor.onSide : Color.primary)
            .padding(NBSpacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(background)
            .contentShape(Circle())
            .frame(maxWidth: NBLayout.sideCircleMaxDiameter)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(String(localized: "\(side.title) side"))
        .accessibilityIdentifier("sideButton.\(side.rawValue)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(mode == .active ? .isSelected : [])
    }

    private var isFilled: Bool {
        switch mode {
        case .active, .start(suggested: true): true
        default: false
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch mode {
        case .start(let suggested):
            Text(suggested ? LocalizedStringKey("Suggested") : LocalizedStringKey("Start"))
        case .active:
            HStack(spacing: NBSpacing.xs) {
                LiveDot(color: NBColor.onSide)
                Text("Tap to pause")
            }
        case .switchTo:
            Text("Tap to switch").foregroundStyle(NBColor.secondaryText)
        case .resumeHere:
            Text("Resume here").foregroundStyle(NBColor.secondaryText)
        }
    }

    @ViewBuilder
    private var background: some View {
        let tint = NBColor.side(side)
        let shape = Circle()
        switch mode {
        case .active:
            // A soft halo marks the running side without relying on color alone ("Active" is
            // also written inside).
            shape.fill(tint)
                .background(shape.fill(tint.opacity(0.22)).padding(-7))
        case .start(suggested: true):
            shape.fill(tint.opacity(0.85))
        case .resumeHere(wasLast: true):
            shape.fill(NBColor.card).overlay { shape.strokeBorder(tint, lineWidth: 3) }
        default:
            shape.fill(NBColor.card).overlay { shape.strokeBorder(tint, lineWidth: 2) }
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        switch mode {
        case .start(let suggested): if suggested { parts.append(String(localized: "suggested")) }
        case .active: parts.append(String(localized: "active"))
        case .switchTo: break
        case .resumeHere: parts.append(String(localized: "paused"))
        }
        if let elapsed { parts.append(DurationText.spoken(elapsed)) }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        switch mode {
        case .start: String(localized: "Starts a feed on the \(side.title.lowercased()) side")
        case .active: String(localized: "Pauses the feed")
        case .switchTo: String(localized: "Switches to the \(side.title.lowercased()) side")
        case .resumeHere: String(localized: "Resumes on the \(side.title.lowercased()) side")
        }
    }
}

/// Slight shrink on press, without changing colors.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Modes") {
    ScrollView {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SideButton(side: .left, mode: .start(suggested: false), elapsed: nil) {}
                SideButton(side: .right, mode: .start(suggested: true), elapsed: nil) {}
            }
            HStack(spacing: 12) {
                SideButton(side: .left, mode: .active, elapsed: 725) {}
                SideButton(side: .right, mode: .switchTo, elapsed: 397) {}
            }
            HStack(spacing: 12) {
                SideButton(side: .left, mode: .resumeHere(wasLast: true), elapsed: 725) {}
                SideButton(side: .right, mode: .resumeHere(wasLast: false), elapsed: 397) {}
            }
        }
        .padding()
    }
    .background(NBColor.canvas)
}
