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
            // The app's Light / Dark / System setting: text and background change together.
            .activityAppearance(context.state.appearance)
            .activityBackgroundTint(ActivityColor.background(context.state.appearance))
            .activitySystemActionForegroundColor(NBColor.accent)
            // Tapping anywhere once a feed has ended opens Home, like the "+".
            .widgetURL(context.state.status == .ended ? NewbeeLink.home : nil)
        } dynamicIsland: { context in
            let state = context.state
            let attributes = context.attributes
            return DynamicIsland {
                // Only the bottom region: the leading and trailing ones beside the camera are too
                // narrow for the status and a clock past an hour (see `IslandExpandedBottom`).
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(attributes: attributes, state: state, isStale: context.isStale)
                        .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                IslandCompactLeading(state: state)
                    .environment(\.colorScheme, .dark)
            } compactTrailing: {
                IslandCompactTrailing(state: state, isStale: context.isStale)
                    .environment(\.colorScheme, .dark)
            } minimal: {
                IslandMinimal(state: state)
                    .environment(\.colorScheme, .dark)
            }
            .widgetURL(state.status == .ended ? NewbeeLink.home : nil)
            .keylineTint(state.status == .ended ? NBColor.side(state.suggestedNextSide) : NBColor.side(state.currentSide))
        }
    }
}
