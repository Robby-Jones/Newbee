import ActivityKit
import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

/// Phase 4 baseline Live Activity: proves the extension, shared attributes and system-driven
/// timer rendering work end to end. The full designs (docs/LIVE_ACTIVITIES.md §3) replace these
/// views in Phase 5.
struct FeedingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeedingActivityAttributes.self) { context in
            LockScreenFeedingView(state: context.state)
                .padding(NBSpacing.l)
                .activityBackgroundTint(NBColor.card)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SideBadge(side: context.state.currentSide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TotalTimerText(state: context.state)
                        .font(NBFont.timer(size: 24))
                }
            } compactLeading: {
                SideBadge(side: context.state.currentSide)
            } compactTrailing: {
                TotalTimerText(state: context.state)
                    .frame(maxWidth: 52)
            } minimal: {
                Circle()
                    .fill(NBColor.side(context.state.currentSide))
                    .frame(width: 12, height: 12)
            }
        }
    }
}

struct LockScreenFeedingView: View {
    let state: FeedingActivityAttributes.ContentState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                Text(state.status == .paused ? "Paused" : "Feeding")
                    .font(.headline)
                TotalTimerText(state: state)
                    .font(NBFont.timer(size: 36))
            }
            Spacer()
            SideBadge(side: state.currentSide)
        }
    }
}

struct SideBadge: View {
    let side: Side

    var body: some View {
        Text(side.shortLabel)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(NBColor.side(side), in: Circle())
            .accessibilityLabel(side == .left ? "Left side" : "Right side")
    }
}

/// Total feeding time. Ticks via the system while active; static when paused or ended.
struct TotalTimerText: View {
    let state: FeedingActivityAttributes.ContentState

    var body: some View {
        if state.status == .active, let start = state.runningTotalTimerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            let total = Duration.seconds(state.leftAccumulated + state.rightAccumulated)
            Text(total, format: .time(pattern: .minuteSecond))
                .monospacedDigit()
        }
    }
}

#Preview("Lock Screen", as: .content, using: FeedingActivityAttributes(sessionID: UUID(), babyName: "")) {
    FeedingLiveActivity()
} contentStates: {
    FeedingActivityAttributes.ContentState(
        status: .active, currentSide: .left, sessionStart: .now.addingTimeInterval(-600),
        currentSegmentStart: .now.addingTimeInterval(-240), leftAccumulated: 0, rightAccumulated: 360,
        pausedAt: nil, revision: 2
    )
    FeedingActivityAttributes.ContentState(
        status: .paused, currentSide: .right, sessionStart: .now.addingTimeInterval(-900),
        currentSegmentStart: nil, leftAccumulated: 420, rightAccumulated: 300,
        pausedAt: .now, revision: 4
    )
}
