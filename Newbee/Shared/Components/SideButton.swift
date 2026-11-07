import NewbeeKit
import NewbeeShared
import SwiftUI

/// One of the two big LEFT / RIGHT controls on the timer screen (docs/UX_SPEC.md §3.3).
/// At least 160 pt tall so it can be hit with a thumb in the dark.
struct SideButton: View {
    enum Mode: Equatable {
        /// No session yet. The suggested side is pre-tinted and tagged.
        case start(suggested: Bool)
        /// This side is running.
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
            VStack(spacing: NBSpacing.s) {
                HStack(spacing: NBSpacing.s) {
                    SideBadge(side: side, style: isFilled ? .onTint : .soft)
                    Text(side.title)
                        .font(.headline)
                }
                if let elapsed {
                    TimerText(elapsed, size: 34, relativeTo: .title)
                } else {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .padding(.vertical, NBSpacing.xs)
                }
                caption
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isFilled ? NBColor.onSide : Color.primary)
            .padding(NBSpacing.l)
            .frame(maxWidth: .infinity, minHeight: NBLayout.sideButtonMinHeight)
            .background(background)
            .contentShape(.rect(cornerRadius: NBRadius.card))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(side.title) side"))
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
                Text("Active")
            }
        case .switchTo:
            Text("Tap to switch").foregroundStyle(.secondary)
        case .resumeHere:
            Text("Resume here").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var background: some View {
        let tint = NBColor.side(side)
        let shape = RoundedRectangle(cornerRadius: NBRadius.card, style: .continuous)
        switch mode {
        case .active:
            shape.fill(tint)
        case .start(suggested: true):
            shape.fill(tint.opacity(0.85))
        case .resumeHere(wasLast: true):
            shape.fill(NBColor.card).overlay { shape.strokeBorder(tint, lineWidth: 3) }
        default:
            shape.fill(NBColor.card).overlay { shape.strokeBorder(tint.opacity(0.6), lineWidth: 2) }
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
        case .active: ""
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
