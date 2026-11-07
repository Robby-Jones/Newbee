#if DEBUG
import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

// Previews for every presentation in active / paused / ended states. Review on a Mac in Xcode
// (Canvas), including dark mode and large Dynamic Type via the canvas variants.

extension FeedingActivityAttributes {
    static var preview: FeedingActivityAttributes {
        FeedingActivityAttributes(sessionID: UUID(), babyName: "")
    }

    static var previewNamed: FeedingActivityAttributes {
        FeedingActivityAttributes(sessionID: UUID(), babyName: "Ada")
    }
}

extension FeedingActivityAttributes.ContentState {
    /// Left running for 4 min after 6 min on the right.
    static var previewActiveLeft: Self {
        Self(
            status: .active, currentSide: .left, sessionStart: .now.addingTimeInterval(-600),
            currentSegmentStart: .now.addingTimeInterval(-240), leftAccumulated: 0, rightAccumulated: 360,
            pausedAt: nil, revision: 2
        )
    }

    /// Right running, second time on the right, long feed (over an hour).
    static var previewActiveLong: Self {
        Self(
            status: .active, currentSide: .right, sessionStart: .now.addingTimeInterval(-4000),
            currentSegmentStart: .now.addingTimeInterval(-300), leftAccumulated: 2100, rightAccumulated: 1500,
            pausedAt: nil, revision: 6
        )
    }

    static var previewPaused: Self {
        Self(
            status: .paused, currentSide: .right, sessionStart: .now.addingTimeInterval(-900),
            currentSegmentStart: nil, leftAccumulated: 420, rightAccumulated: 300,
            pausedAt: .now.addingTimeInterval(-60), revision: 4
        )
    }

    /// The spec example: left 12, right 9.
    static var previewEnded: Self {
        Self(
            status: .ended, currentSide: .right, sessionStart: .now.addingTimeInterval(-1260),
            currentSegmentStart: nil, leftAccumulated: 720, rightAccumulated: 540,
            pausedAt: .now, revision: 5
        )
    }
}

#Preview("Lock Screen", as: .content, using: FeedingActivityAttributes.previewNamed) {
    FeedingLiveActivity()
} contentStates: {
    FeedingActivityAttributes.ContentState.previewActiveLeft
    FeedingActivityAttributes.ContentState.previewActiveLong
    FeedingActivityAttributes.ContentState.previewPaused
    FeedingActivityAttributes.ContentState.previewEnded
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: FeedingActivityAttributes.preview) {
    FeedingLiveActivity()
} contentStates: {
    FeedingActivityAttributes.ContentState.previewActiveLeft
    FeedingActivityAttributes.ContentState.previewPaused
    FeedingActivityAttributes.ContentState.previewEnded
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: FeedingActivityAttributes.preview) {
    FeedingLiveActivity()
} contentStates: {
    FeedingActivityAttributes.ContentState.previewActiveLeft
    FeedingActivityAttributes.ContentState.previewActiveLong
    FeedingActivityAttributes.ContentState.previewPaused
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: FeedingActivityAttributes.preview) {
    FeedingLiveActivity()
} contentStates: {
    FeedingActivityAttributes.ContentState.previewActiveLeft
    FeedingActivityAttributes.ContentState.previewPaused
    FeedingActivityAttributes.ContentState.previewEnded
}
#endif
