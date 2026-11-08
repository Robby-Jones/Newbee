import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

// Dynamic Island presentations (docs/LIVE_ACTIVITIES.md §3.2–3.4). The island is always black,
// so text uses fixed white / gray (`IslandColor`), never `.secondary`, which is dark gray when
// the phone is in light mode. `FeedingLiveActivity` draws every region in the dark scheme so the
// adaptive side and control colors pick their dark-mode values.

enum IslandColor {
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.7)
}

// MARK: Expanded

/// Everything in the expanded island, drawn in its bottom region: the same layouts as the Lock
/// Screen at a smaller scale.
///
/// The leading and trailing regions beside the camera are only about 100 pt wide, too narrow for
/// "Since last feed" or a clock past an hour, which truncated to "Since last…" and "1:00:…"
/// (2026-11-08). The bottom region spans the island's full width.
struct IslandExpandedBottom: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        Group {
            if let since = state.sinceLastFeedStart {
                ActivitySinceLastFeedContent(state: state, isStale: isStale, since: since, style: .island)
            } else {
                ActivityFeedingContent(attributes: attributes, state: state, isStale: isStale, style: .island)
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
            Image(systemName: "clock")
                .font(.caption.weight(.bold))
                .foregroundStyle(IslandColor.secondaryText)
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
        case .paused: IslandColor.secondaryText
        case .ended: IslandColor.primaryText
        }
    }

    /// "45:12" fits 50 pt; past an hour ("1:02:03") needs about 56, so 64 leaves room for wider
    /// digits and bold text. The time since the last feed is usually past an hour.
    private var maxWidth: CGFloat {
        state.status == .ended || state.totalAccumulated >= 3600 ? 64 : 50
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
                Circle().strokeBorder(IslandColor.secondaryText, lineWidth: 2)
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IslandColor.secondaryText)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.statusLine(isStale: false))
    }
}
