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

/// "L 12:05" with the running side emphasised.
struct SideRow: View {
    let state: FeedingState
    let side: Side
    var fontSize: CGFloat = 17

    var body: some View {
        let running = state.isRunning(side)
        HStack(spacing: NBSpacing.s) {
            SideBadge(side: side, size: fontSize + 5, filled: running || state.currentSide == side)
            SideTimerText(state: state, side: side)
                .font(.system(size: fontSize, weight: running ? .bold : .regular, design: .rounded))
                .foregroundStyle(running ? Color.primary : Color.secondary)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: fontSize * 3.2, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side.displayName + (running ? ", running" : ""))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        if state.isRunning(side), let start = state.runningSideTimerStart {
            return Text(timerInterval: start...Date.distantFuture, countsDown: false)
        }
        return Text(LiveActivityFormat.spoken(state.accumulated(on: side)))
    }
}

/// A capsule-backed control for Live Activity buttons. At least 44 pt tall for one-handed use.
struct ActivityControlLabel: View {
    let title: String
    let systemImage: String?
    let tint: Color
    var prominent = false

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
        .foregroundStyle(prominent ? Color.white : tint)
        .padding(.horizontal, NBSpacing.m)
        .frame(minWidth: 44, minHeight: 44)
        .background(
            Capsule().fill(prominent ? tint : tint.opacity(0.18))
        )
        .contentShape(Capsule())
    }
}

/// End is deliberately a different shape (rounded square) and sits apart from the other
/// controls, so it isn't hit by accident.
struct EndControlLabel: View {
    var body: some View {
        Image(systemName: "stop.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(NBColor.destructive)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NBColor.destructive, lineWidth: 2)
            )
            .contentShape(Rectangle())
    }
}

/// Pause or resume, whichever applies.
struct PauseResumeButton: View {
    let sessionID: UUID
    let state: FeedingState
    var compact = false

    var body: some View {
        if state.status == .paused {
            Button(intent: ResumeFeedingIntent(sessionID: sessionID)) {
                ActivityControlLabel(
                    title: compact ? "" : "Resume", systemImage: "play.fill",
                    tint: NBColor.side(state.currentSide)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume on \(state.currentSide.displayName.lowercased())")
        } else {
            Button(intent: PauseFeedingIntent(sessionID: sessionID)) {
                ActivityControlLabel(title: compact ? "" : "Pause", systemImage: "pause.fill", tint: NBColor.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause feeding")
        }
    }
}

struct EndButton: View {
    let sessionID: UUID

    var body: some View {
        Button(intent: EndFeedingIntent(sessionID: sessionID)) {
            EndControlLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End feeding")
    }
}

/// "L" or "R" switch control. Tapping the running side is harmless (target-state intent).
struct SideSwitchButton: View {
    let sessionID: UUID
    let state: FeedingState
    let side: Side
    var title: String? = nil

    var body: some View {
        let selected = state.isRunning(side)
        Button(intent: SwitchFeedingSideIntent(sessionID: sessionID, side: side)) {
            ActivityControlLabel(
                title: title ?? side.shortLabel,
                systemImage: nil,
                tint: NBColor.side(side),
                prominent: !selected
            )
            .overlay {
                if selected {
                    Capsule().strokeBorder(NBColor.side(side), lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            selected ? "Feeding on \(side.displayName.lowercased())"
                : state.status == .paused ? "Resume on \(side.displayName.lowercased())"
                : "Switch to \(side.displayName.lowercased())"
        )
    }
}
