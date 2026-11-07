#if canImport(ActivityKit)
import ActivityKit
import Foundation
import NewbeeKit

/// Live Activity model shared by the app (which starts and updates activities) and the widget
/// extension (which renders them). See docs/LIVE_ACTIVITIES.md §2.
///
/// Static properties identify the session; `ContentState` carries only timestamps and
/// accumulated durations, so the system can render a ticking timer with no updates from the app.
public struct FeedingActivityAttributes: ActivityAttributes {
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

        public init(
            status: Status,
            currentSide: Side,
            sessionStart: Date,
            currentSegmentStart: Date?,
            leftAccumulated: TimeInterval,
            rightAccumulated: TimeInterval,
            pausedAt: Date?,
            revision: Int
        ) {
            self.status = status
            self.currentSide = currentSide
            self.sessionStart = sessionStart
            self.currentSegmentStart = currentSegmentStart
            self.leftAccumulated = leftAccumulated
            self.rightAccumulated = rightAccumulated
            self.pausedAt = pausedAt
            self.revision = revision
        }

        public func accumulated(on side: Side) -> TimeInterval {
            side == .left ? leftAccumulated : rightAccumulated
        }

        /// A start date that, fed to a counting-up `Text(timerInterval:)`, shows the running
        /// side's total time including its earlier segments.
        public var runningSideTimerStart: Date? {
            currentSegmentStart?.addingTimeInterval(-accumulated(on: currentSide))
        }

        /// A start date that shows the session's total feeding time when counting up.
        public var runningTotalTimerStart: Date? {
            currentSegmentStart?.addingTimeInterval(-(leftAccumulated + rightAccumulated))
        }
    }
}
#endif
