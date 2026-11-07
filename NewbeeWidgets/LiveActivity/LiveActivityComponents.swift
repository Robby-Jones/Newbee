import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

typealias FeedingState = FeedingActivityAttributes.ContentState

extension Side {
    var displayName: String { self == .left ? "Left" : "Right" }
}

extension FeedingState {
    /// One-line status, e.g. "Feeding on left", "Paused", "Feed complete".
    func statusLine(isStale: Bool) -> String {
        if isStale && status != .ended { return "Still feeding? Open Newbee" }
        switch status {
        case .active: return "Feeding on \(currentSide.displayName.lowercased())"
        case .paused: return "Paused"
        case .ended: return "Feed complete"
        }
    }
}

/// "L" / "R" in a side-colored circle. Color is never the only signal.
struct SideBadge: View {
    let side: Side
    var size: CGFloat = 28
    /// Hollow when the side isn't running (paused or ended).
    var filled: Bool = true

    var body: some View {
        Text(side.shortLabel)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? Color.white : NBColor.side(side))
            .frame(width: size, height: size)
            .background {
                if filled {
                    Circle().fill(NBColor.side(side))
                } else {
                    Circle().strokeBorder(NBColor.side(side), lineWidth: 2)
                }
            }
            .accessibilityLabel("\(side.displayName) side")
    }
}

/// Total feeding time (pauses excluded). Ticks via the system while active; frozen otherwise.
struct TotalTimerText: View {
    let state: FeedingState

    var body: some View {
        if state.status == .active, let start = state.runningTotalTimerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .accessibilityLabel(Text("Total feeding time"))
                .accessibilityValue(Text(timerInterval: start...Date.distantFuture, countsDown: false))
        } else {
            Text(LiveActivityFormat.clock(state.totalAccumulated))
                .monospacedDigit()
                .accessibilityLabel("Total feeding time")
                .accessibilityValue(LiveActivityFormat.spoken(state.totalAccumulated))
        }
    }
}

/// Time on one side. Ticks only for the running side.
struct SideTimerText: View {
    let state: FeedingState
    let side: Side

    var body: some View {
        if state.isRunning(side), let start = state.runningSideTimerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        } else {
            Text(LiveActivityFormat.clock(state.accumulated(on: side)))
                .monospacedDigit()
        }
    }
}

/// Dark text on a filled side color: white would fall below WCAG AA on the light side tints.
private let textOnSide = Color(light: 0x1B1B20, dark: 0x0F0F12)

/// "Feeding", "Paused" or "Feed complete" with a small glyph: one quiet line instead of a badge
/// and a status label.
struct ActivityStatusLabel: View {
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        HStack(spacing: NBSpacing.xs) {
            Text(text)
                .lineLimit(1)
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(symbolColor)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.statusLine(isStale: isStale))
    }

    private var showsStale: Bool { isStale && state.status != .ended }

    private var text: String {
        if showsStale { return "Still feeding?" }
        switch state.status {
        case .active: return "Feeding"
        case .paused: return "Paused"
        case .ended: return "Feed complete"
        }
    }

    private var symbol: String {
        if showsStale { return "questionmark.circle" }
        switch state.status {
        case .active: return "drop.fill"
        case .paused: return "pause.fill"
        case .ended: return "checkmark"
        }
    }

    private var symbolColor: Color {
        state.status == .active && !showsStale ? NBColor.side(state.currentSide) : Color.secondary
    }
}

/// One side's time as a pill: "L 12:05". The running side is filled with its color.
///
/// While a feed is open, the pill is the side-switch control: tapping the other side switches to
/// it, or resumes on it when paused. Tapping the running side changes nothing, because the
/// intent targets a state rather than toggling. After the feed ends the pills only show times.
struct SidePill: View {
    let sessionID: UUID
    let state: FeedingState
    let side: Side

    var body: some View {
        if state.status == .ended {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(side.displayName) side")
                .accessibilityValue(LiveActivityFormat.spoken(state.accumulated(on: side)))
        } else {
            Button(intent: SwitchFeedingSideIntent(sessionID: sessionID, side: side)) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
        }
    }

    private var label: some View {
        let running = state.isRunning(side)
        let pausedHere = state.status == .paused && state.currentSide == side
        let tint = NBColor.side(side)
        return HStack(spacing: NBSpacing.s) {
            Text(side.shortLabel)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            SideTimerText(state: state, side: side)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                // Timer text otherwise claims all available width.
                .frame(maxWidth: 72)
        }
        .foregroundStyle(running ? textOnSide : tint)
        .padding(.horizontal, NBSpacing.m)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Capsule().fill(running ? tint : tint.opacity(pausedHere ? 0.3 : 0.16)))
        .contentShape(Capsule())
    }

    private var accessibilityLabel: String {
        if state.isRunning(side) { return "Feeding on \(side.displayName.lowercased())" }
        if state.status == .paused { return "Resume on \(side.displayName.lowercased())" }
        return "Switch to \(side.displayName.lowercased())"
    }

    private var accessibilityValue: Text {
        if state.isRunning(side), let start = state.runningSideTimerStart {
            return Text(timerInterval: start...Date.distantFuture, countsDown: false)
        }
        return Text(LiveActivityFormat.spoken(state.accumulated(on: side)))
    }
}

/// A capsule-backed control with a label, used for "Undo". At least 44 pt tall.
struct ActivityControlLabel: View {
    let title: String
    let systemImage: String?
    let tint: Color

    var body: some View {
        HStack(spacing: NBSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            if !title.isEmpty {
                Text(title).lineLimit(1)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, NBSpacing.m)
        .frame(minWidth: 44, minHeight: 44)
        .background(Capsule().fill(tint.opacity(0.18)))
        .contentShape(Capsule())
    }
}

/// A round 44 pt icon control on a soft tint of its color.
struct ActivityCircleLabel: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Circle().fill(tint.opacity(0.18)))
            .contentShape(Circle())
    }
}

/// Pause or resume, whichever applies. Resume continues on the side that was running.
struct PauseResumeButton: View {
    let sessionID: UUID
    let state: FeedingState

    var body: some View {
        if state.status == .paused {
            Button(intent: ResumeFeedingIntent(sessionID: sessionID)) {
                ActivityCircleLabel(systemImage: "play.fill", tint: NBColor.side(state.currentSide))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume on \(state.currentSide.displayName.lowercased())")
        } else {
            Button(intent: PauseFeedingIntent(sessionID: sessionID)) {
                ActivityCircleLabel(systemImage: "pause.fill", tint: NBColor.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause feeding")
        }
    }
}

/// End is the only control in the destructive color, and sits last with extra space before it
/// so it isn't hit by accident.
struct EndButton: View {
    let sessionID: UUID

    var body: some View {
        Button(intent: EndFeedingIntent(sessionID: sessionID)) {
            ActivityCircleLabel(systemImage: "stop.fill", tint: NBColor.destructive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End feeding")
    }
}

/// The side pills and the controls, shared by the Lock Screen and the expanded Dynamic Island so
/// both read the same way.
///
/// ```
///  [ L 12:05 ] [ R 6:37 ]  (⏸)  (■)
/// ```
struct ActivitySidesAndControls: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState

    var body: some View {
        HStack(spacing: NBSpacing.s) {
            SidePill(sessionID: attributes.sessionID, state: state, side: .left)
            SidePill(sessionID: attributes.sessionID, state: state, side: .right)
            if state.status == .ended {
                UndoEndButton(sessionID: attributes.sessionID)
            } else {
                PauseResumeButton(sessionID: attributes.sessionID, state: state)
                EndButton(sessionID: attributes.sessionID)
                    .padding(.leading, NBSpacing.xs)
            }
        }
    }
}

/// "Undo" on the "Feed complete" summary, for an End tapped by mistake.
struct UndoEndButton: View {
    let sessionID: UUID

    var body: some View {
        Button(intent: UndoEndFeedingIntent(sessionID: sessionID)) {
            ActivityControlLabel(title: "Undo", systemImage: "arrow.uturn.backward", tint: NBColor.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo end feeding")
        .accessibilityHint("Reopens the feed you just ended")
    }
}
