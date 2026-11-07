import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

// Dynamic Island presentations (docs/LIVE_ACTIVITIES.md §3.2–3.4). The island is always dark,
// so text uses white/secondary and side colors carry the identity.

// MARK: Expanded

struct IslandExpandedLeading: View {
    let state: FeedingState

    var body: some View {
        HStack(spacing: NBSpacing.s) {
            SideBadge(side: state.currentSide, size: 30, filled: state.status == .active)
            Text(state.currentSide.displayName)
                .font(.headline)
                .foregroundStyle(NBColor.side(state.currentSide))
        }
        .padding(.leading, NBSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

struct IslandExpandedTrailing: View {
    let state: FeedingState

    var body: some View {
        TotalTimerText(state: state)
            .font(NBFont.timer(size: 28))
            .foregroundStyle(state.status == .active ? Color.white : Color.secondary)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110, alignment: .trailing)
            .padding(.trailing, NBSpacing.xs)
    }
}

struct IslandExpandedCenter: View {
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        Text(state.statusLine(isStale: isStale))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct IslandExpandedBottom: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState

    var body: some View {
        VStack(spacing: NBSpacing.s) {
            HStack {
                SideRow(state: state, side: .left, fontSize: 15)
                Spacer()
                SideRow(state: state, side: .right, fontSize: 15)
            }
            if state.status != .ended {
                HStack(spacing: NBSpacing.s) {
                    // Only the other side is offered: one big, obvious action in a small space.
                    let other = state.status == .active ? state.currentSide.opposite : state.currentSide
                    SideSwitchButton(
                        sessionID: attributes.sessionID, state: state, side: other,
                        title: state.status == .active ? "Switch to \(other.shortLabel)" : "Resume \(other.shortLabel)"
                    )
                    .frame(maxWidth: .infinity)
                    PauseResumeButton(sessionID: attributes.sessionID, state: state, compact: true)
                    EndButton(sessionID: attributes.sessionID)
                }
            }
        }
        .padding(.horizontal, NBSpacing.xs)
    }
}

// MARK: Compact

struct IslandCompactLeading: View {
    let state: FeedingState

    var body: some View {
        switch state.status {
        case .active:
            SideBadge(side: state.currentSide, size: 22)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(NBColor.side(state.currentSide))
                .accessibilityLabel("Paused")
        case .ended:
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(NBColor.side(state.currentSide))
                .accessibilityLabel("Feed complete")
        }
    }
}

struct IslandCompactTrailing: View {
    let state: FeedingState

    var body: some View {
        TotalTimerText(state: state)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(state.status == .active ? NBColor.side(state.currentSide) : Color.secondary)
            .multilineTextAlignment(.trailing)
            // Timer text otherwise claims all available width and pushes the island wide.
            .frame(maxWidth: state.totalAccumulated >= 3600 ? 60 : 46)
    }
}

// MARK: Minimal

struct IslandMinimal: View {
    let state: FeedingState

    var body: some View {
        let color = NBColor.side(state.currentSide)
        ZStack {
            switch state.status {
            case .active:
                Circle().fill(color)
                Image(systemName: "drop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            case .paused:
                Circle().strokeBorder(color, lineWidth: 2)
                Image(systemName: "pause.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
            case .ended:
                Circle().strokeBorder(color, lineWidth: 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.statusLine(isStale: false))
    }
}
