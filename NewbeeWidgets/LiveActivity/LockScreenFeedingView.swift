import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

/// Lock Screen and banner presentation (docs/LIVE_ACTIVITIES.md §3.1).
///
/// Mirrors the expanded Dynamic Island so the activity looks and works the same wherever the
/// parent sees it: current side and status on the left, total on the right, then the per-side
/// times and a single "Switch to" button with pause and end.
///
/// ```
///  (L) Left                                 18:42
///      Feeding on left
///  L  12:05                              R   6:37
///  [       Switch to R       ]     [⏸]     [■]
/// ```
struct LockScreenFeedingView: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        VStack(spacing: NBSpacing.m) {
            header
            ActivitySidesAndControls(attributes: attributes, state: state, sideFontSize: 16)
            if state.status == .ended {
                endedFooter
            }
        }
        .padding(NBSpacing.l)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: NBSpacing.s) {
            SideBadge(side: state.currentSide, size: 30, filled: state.status == .active)
            VStack(alignment: .leading, spacing: 0) {
                Text(state.currentSide.displayName)
                    .font(.headline)
                    .foregroundStyle(NBColor.side(state.currentSide))
                Text(state.statusLine(isStale: isStale))
                    .font(.subheadline)
                    .foregroundStyle(state.status == .paused || isStale ? NBColor.accent : Color.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: NBSpacing.s)
            TotalTimerText(state: state)
                .font(NBFont.timer(size: 32))
                .foregroundStyle(state.status == .active ? Color.primary : Color.secondary)
                .multilineTextAlignment(.trailing)
                // Timer text otherwise claims all available width.
                .frame(maxWidth: 130, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var endedFooter: some View {
        if let endedAt = state.pausedAt {
            Text("Started \(state.sessionStart, style: .time) · ended \(endedAt, style: .time)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
