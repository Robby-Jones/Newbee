import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

/// Lock Screen and banner presentation (docs/LIVE_ACTIVITIES.md §3.1).
///
/// Mirrors the expanded Dynamic Island so the activity looks and works the same wherever the
/// parent sees it. Minimal: the total and a quiet status on one line, then the two side pills
/// (each shows its own time and switches to that side) with pause and end.
///
/// ```
///  18:42                                Feeding 💧
///  [  L 12:05  ] [  R 6:37  ]   (⏸)   (■)
/// ```
struct LockScreenFeedingView: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        VStack(spacing: NBSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: NBSpacing.s) {
                TotalTimerText(state: state)
                    .font(NBFont.timer(size: 30))
                    .foregroundStyle(state.status == .active ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.leading)
                    // Timer text otherwise claims all available width.
                    .frame(maxWidth: 150, alignment: .leading)
                Spacer(minLength: NBSpacing.s)
                ActivityStatusLabel(state: state, isStale: isStale)
            }
            ActivitySidesAndControls(attributes: attributes, state: state)
            if state.status == .ended {
                endedFooter
            }
        }
        .padding(NBSpacing.l)
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
