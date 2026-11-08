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
///
/// After the feed ends, the same activity counts the time since, with Start buttons and a line
/// about the feed that ended:
///
/// ```
///  2:15                          Since last feed 🕒
///  [   ▶ Left   ] [   ▶ Right   ]
///  Last feed L 12:05 · R 9:00 · ended 3:40 PM
/// ```
struct LockScreenFeedingView: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        VStack(spacing: NBSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: NBSpacing.s) {
                HeadlineTimerText(state: state, isStale: isStale)
                    .font(NBFont.timer(size: 30))
                    .foregroundStyle(state.status == .paused ? Color.secondary : Color.primary)
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
        if let endedAt = state.lastFeedEndedAt {
            let left = LiveActivityFormat.clock(state.leftAccumulated)
            let right = LiveActivityFormat.clock(state.rightAccumulated)
            Text("Last feed L \(left) · R \(right) · ended \(endedAt, style: .time)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(
                    "Last feed: left \(LiveActivityFormat.spoken(state.leftAccumulated)), right \(LiveActivityFormat.spoken(state.rightAccumulated)), ended \(endedAt.formatted(date: .omitted, time: .shortened))"
                )
        }
    }
}
