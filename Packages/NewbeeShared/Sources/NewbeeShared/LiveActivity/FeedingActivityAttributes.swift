import Foundation
import NewbeeKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Live Activity model shared by the app (which starts and updates activities) and the widget
/// extension (which renders them). See docs/LIVE_ACTIVITIES.md §2.
///
/// Static properties identify the session; `ContentState` carries only timestamps and
/// accumulated durations, so the system can render a ticking timer with no updates from the app.
///
/// The struct itself is platform-independent so the mapping and planning logic can be unit tested
/// on Linux; the `ActivityAttributes` conformance is added below where ActivityKit exists.
public struct FeedingActivityAttributes: Codable, Hashable, Sendable {
    public var sessionID: UUID
    public var babyName: String
    public var schemaVersion: Int

    public init(sessionID: UUID, babyName: String, schemaVersion: Int = 1) {
        self.sessionID = sessionID
        self.babyName = babyName
        self.schemaVersion = schemaVersion
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public enum Status: String, Codable, Hashable, Sendable {
            case active
            case paused
            /// No feed is running. The activity counts up the time since this feed ended
            /// (`pausedAt`), and still carries the finished feed's side times.
            case ended
        }

        public var status: Status
        /// The running side, or the last side used while paused or ended.
        public var currentSide: Side
        public var sessionStart: Date
        /// Start of the running segment; `nil` when paused or ended.
        public var currentSegmentStart: Date?
        /// Time on each side from closed segments only.
        public var leftAccumulated: TimeInterval
        public var rightAccumulated: TimeInterval
        public var pausedAt: Date?
        /// Mirrors `SessionSnapshot.revision`.
        public var revision: Int
        /// The session this content describes. Set by `init(snapshot:)`; it differs from
        /// `FeedingActivityAttributes.sessionID` when an activity is carried over to another feed
        /// (since-last-feed after the newest feed was deleted, or a feed started from the Lock
        /// Screen when a new activity couldn't be requested). `nil` in content from older builds.
        public var sessionID: UUID?

        public init(
            status: Status,
            currentSide: Side,
            sessionStart: Date,
            currentSegmentStart: Date?,
            leftAccumulated: TimeInterval,
            rightAccumulated: TimeInterval,
            pausedAt: Date?,
            revision: Int,
            sessionID: UUID? = nil
        ) {
            self.status = status
            self.currentSide = currentSide
            self.sessionStart = sessionStart
            self.currentSegmentStart = currentSegmentStart
            self.leftAccumulated = leftAccumulated
            self.rightAccumulated = rightAccumulated
            self.pausedAt = pausedAt
            self.revision = revision
            self.sessionID = sessionID
        }

        public func accumulated(on side: Side) -> TimeInterval {
            side == .left ? leftAccumulated : rightAccumulated
        }

        /// A start date that, fed to a counting-up `Text(timerInterval:)`, shows the running
        /// side's total time including its earlier segments.
        public var runningSideTimerStart: Date? {
            currentSegmentStart?.addingTimeInterval(-accumulated(on: currentSide))
        }

        /// When the last feed ended, while no feed is running: the start of the since-last-feed count.
        public var lastFeedEndedAt: Date? {
            status == .ended ? pausedAt : nil
        }

        /// A start date that shows the session's total feeding time when counting up.
        public var runningTotalTimerStart: Date? {
            currentSegmentStart?.addingTimeInterval(-(leftAccumulated + rightAccumulated))
        }
    }
}

#if canImport(ActivityKit)
extension FeedingActivityAttributes: ActivityAttributes {}
#endif
