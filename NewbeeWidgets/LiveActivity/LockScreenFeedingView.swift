import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

/// Lock Screen and banner presentation (docs/LIVE_ACTIVITIES.md §3.1).
///
/// Mirrors the expanded Dynamic Island so the activity looks and works the same wherever the
/// parent sees it. While a feed is open: the total and a quiet status on one line, then the two
/// side pills (each shows its own time and switches to that side) with pause and end.
///
/// ```
///  18:42                                Feeding 💧
///  [  L 12:05  ] [  R 6:37  ]   (⏸)   (■)
/// ```
///
/// After the feed ends, the same activity counts the time since it, large, with one "+" that
/// opens the app on Home, and a line about that feed:
///
/// ```
///  Since last feed 🕒
///  2:15:03                                   (+)
///  Last feed L 12:05 · R 9:00 · ended 3:40 PM
/// ```
///
/// Colors come from `ActivityColor` and follow the app's Light / Dark / System setting
/// (`ContentState.appearance`), applied by `FeedingLiveActivity`.
struct LockScreenFeedingView: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        if let since = state.sinceLastFeedStart {
            sinceLastFeed(since)
        } else {
            feeding
        }
    }

    private var feeding: some View {
        VStack(spacing: NBSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: NBSpacing.s) {
                TotalTimerText(state: state)
                    .font(NBFont.timer(size: 30))
                    .foregroundStyle(state.status == .paused ? ActivityColor.secondaryText : ActivityColor.primaryText)
                    .multilineTextAlignment(.leading)
                    // Timer text otherwise claims all available width.
                    .frame(maxWidth: 150, alignment: .leading)
                Spacer(minLength: NBSpacing.s)
                ActivityStatusLabel(state: state, isStale: isStale)
            }
            ActivitySidesAndControls(attributes: attributes, state: state)
        }
        .padding(NBSpacing.l)
    }

    private func sinceLastFeed(_ since: Date) -> some View {
        VStack(alignment: .leading, spacing: NBSpacing.s) {
            HStack(alignment: .center, spacing: NBSpacing.m) {
                VStack(alignment: .leading, spacing: 0) {
                    ActivityStatusLabel(state: state, isStale: isStale)
                    SinceLastFeedText(since: since)
                        .font(NBFont.timer(size: 44))
                        .foregroundStyle(ActivityColor.primaryText)
                        .multilineTextAlignment(.leading)
                        // Timer text otherwise claims all available width; "12:05:00" fits.
                        .frame(maxWidth: 220, alignment: .leading)
                }
                Spacer(minLength: NBSpacing.s)
                NewFeedButton()
            }
            LastFeedLine(state: state)
                .foregroundStyle(ActivityColor.secondaryText)
        }
        .padding(NBSpacing.l)
    }
}
