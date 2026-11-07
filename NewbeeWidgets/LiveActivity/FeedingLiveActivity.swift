import ActivityKit
import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

/// The feeding Live Activity: Lock Screen / banner plus every Dynamic Island presentation
/// (docs/LIVE_ACTIVITIES.md §3).
///
/// Views render `ContentState` only. Running values tick via system timers
/// (`Text(timerInterval:)`), so the app never has to push updates while a side is running.
struct FeedingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeedingActivityAttributes.self) { context in
            LockScreenFeedingView(
                attributes: context.attributes,
                state: context.state,
                isStale: context.isStale
            )
            .activityBackgroundTint(NBColor.card)
            .activitySystemActionForegroundColor(NBColor.accent)
        } dynamicIsland: { context in
            let state = context.state
            let attributes = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivitySidesAndControls(attributes: attributes, state: state)
                        .padding(.horizontal, NBSpacing.xs)
                }
            } compactLeading: {
                IslandCompactLeading(state: state)
            } compactTrailing: {
                IslandCompactTrailing(state: state)
            } minimal: {
                IslandMinimal(state: state)
            }
            .keylineTint(NBColor.side(state.currentSide))
        }
    }
}
