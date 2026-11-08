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
            /// No feed is running. The activity counts up the time since the latest feed ended
            /// (`pausedAt`). For a breastfeed it still carries the side times; for a bottle,
            /// `lastBottle` is set and the side times are zero.
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
        /// The amount, while counting from a bottle (then `sessionID` is the bottle's id).
        /// `nil` otherwise, and in content from older builds.
        public var lastBottle: BottleAmount?
        /// The app's Light / Dark / System setting, so the Lock Screen activity matches the app.
        /// `nil` in content from older builds, which is drawn as `.system`.
        public var appearance: LiveActivityAppearance?
        /// Settings' "Count from": the since-last-feed count runs from the last feed's start
        /// (`.start`) or end. `nil` means the end (and is what older builds sent).
        public var countFrom: ReminderSettings.Basis?

        public init(
            status: Status,
            currentSide: Side,
            sessionStart: Date,
            currentSegmentStart: Date?,
            leftAccumulated: TimeInterval,
            rightAccumulated: TimeInterval,
            pausedAt: Date?,
            revision: Int,
            sessionID: UUID? = nil,
            lastBottle: BottleAmount? = nil,
            appearance: LiveActivityAppearance? = nil,
            countFrom: ReminderSettings.Basis? = nil
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
            self.lastBottle = lastBottle
            self.appearance = appearance
            self.countFrom = countFrom
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

        /// What the since-last-feed count runs from, while no feed is running: the last feed's
        /// start or end, per `countFrom`.
        public var sinceLastFeedStart: Date? {
            guard status == .ended else { return nil }
            return countFrom == .start ? sessionStart : pausedAt
        }

        /// A start date that shows the session's total feeding time when counting up.
        public var runningTotalTimerStart: Date? {
            currentSegmentStart?.addingTimeInterval(-(leftAccumulated + rightAccumulated))
        }
    }
}

/// The app's appearance setting, carried to the Live Activity (`ContentState.appearance`).
public enum LiveActivityAppearance: String, Codable, Hashable, Sendable {
    case system, light, dark
}

/// Links into the app from the Live Activity.
public enum NewbeeLink {
    /// Opens the app on Home.
    public static let home = URL(string: "newbee://home")!
}

#if canImport(ActivityKit)
extension FeedingActivityAttributes: ActivityAttributes {}
#endif
