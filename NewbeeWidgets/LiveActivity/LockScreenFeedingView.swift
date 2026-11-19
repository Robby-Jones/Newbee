import NewbeeKit
import NewbeeShared
import SwiftUI
import UIKit
import WidgetKit

/// Lock Screen and banner presentation (docs/LIVE_ACTIVITIES.md §3.1).
///
/// Draws the same shared layouts as the expanded Dynamic Island (`ActivityFeedingContent`,
/// `SinceLastFeedActivityContent`) so the activity looks and works the same wherever the parent
/// sees it. While a feed is open: the total and a quiet status on one line, then the two
/// side pills (each shows its own time and switches to that side) with pause and end.
///
/// ```
///  18:42                                Feeding 💧
///  [  L 12:05  ] [  R 6:37  ]   (⏸)   (■)
/// ```
///
/// After the feed ends, the same activity shows the baby, how long ago and when they last fed,
/// what that feed was, and one "+" that opens the app on Home:
///
/// ```
///   (photo)🐝      28 min, 30 sec ago
///                Last fed: 10:33 PM          (+)
///    Millie         (🍼) 1 oz
/// ```
///
/// Always dark: a black card (`ActivityPalette`), whatever the phone's or the app's appearance.
struct LockScreenFeedingView: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState
    let isStale: Bool
    /// The baby's photo from the App Group (`LiveActivityAvatar`).
    var photo: UIImage? = LiveActivityAvatar.load()

    var body: some View {
        Group {
            if let since = state.sinceLastFeedStart {
                SinceLastFeedActivityContent(
                    state: state, babyName: attributes.babyName, since: since, style: .lockScreen, photo: photo
                )
            } else {
                ActivityFeedingContent(attributes: attributes, state: state, isStale: isStale, style: .lockScreen)
            }
        }
        .padding(NBSpacing.l)
    }
}
