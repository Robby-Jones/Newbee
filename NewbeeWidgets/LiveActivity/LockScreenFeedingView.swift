import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

/// Lock Screen and banner presentation (docs/LIVE_ACTIVITIES.md §3.1).
///
/// Draws the same shared layouts as the expanded Dynamic Island (`ActivityFeedingContent`,
/// `ActivitySinceLastFeedContent`) so the activity looks and works the same wherever the parent
/// sees it. While a feed is open: the total and a quiet status on one line, then the two
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
        Group {
            if let since = state.sinceLastFeedStart {
                ActivitySinceLastFeedContent(state: state, isStale: isStale, since: since, style: .lockScreen)
            } else {
                ActivityFeedingContent(attributes: attributes, state: state, isStale: isStale, style: .lockScreen)
            }
        }
        .padding(NBSpacing.l)
    }
}
