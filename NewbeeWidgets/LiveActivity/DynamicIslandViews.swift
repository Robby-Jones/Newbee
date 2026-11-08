import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

// Dynamic Island presentations (docs/LIVE_ACTIVITIES.md §3.2–3.4). The island is always dark,
// so text uses white/secondary and side colors carry the identity.

// MARK: Expanded

/// The total, or the time since the last feed once it has ended.
struct IslandExpandedLeading: View {
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        HeadlineTimerText(state: state, isStale: isStale)
            .font(NBFont.timer(size: 26))
            .foregroundStyle(state.status == .paused ? Color.secondary : Color.white)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 120, alignment: .leading)
            .padding(.leading, NBSpacing.xs)
    }
}

struct IslandExpandedTrailing: View {
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        ActivityStatusLabel(state: state, isStale: isStale)
            .padding(.trailing, NBSpacing.xs)
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
            Image(systemName: "clock")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.secondary)
                .accessibilityLabel("Since last feed")
        }
    }
}

struct IslandCompactTrailing: View {
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        HeadlineTimerText(state: state, isStale: isStale)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .multilineTextAlignment(.trailing)
            // Timer text otherwise claims all available width and pushes the island wide.
            .frame(maxWidth: maxWidth)
    }

    private var foreground: Color {
        switch state.status {
        case .active: NBColor.side(state.currentSide)
        case .paused: Color.secondary
        case .ended: Color.white
        }
    }

    /// "12:05" since last feed fits the narrow width; a feed over an hour needs "1:02:03".
    private var maxWidth: CGFloat {
        state.status != .ended && state.totalAccumulated >= 3600 ? 60 : 46
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
                Circle().strokeBorder(Color.secondary, lineWidth: 2)
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.statusLine(isStale: false))
    }
}
