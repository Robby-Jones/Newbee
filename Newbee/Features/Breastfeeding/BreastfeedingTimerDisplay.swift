import Foundation
import NewbeeKit

/// Everything the timer screen draws, derived from a snapshot and `now`. Pure and unit tested.
/// Keeps views free of logic: the view renders this, re-computed once a second by `TimelineView`.
struct BreastfeedingTimerDisplay: Equatable {
    enum Phase: Equatable {
        case notStarted
        case active(Side)
        case paused(lastSide: Side?)
    }

    var phase: Phase
    /// Total feeding time (pauses excluded).
    var total: TimeInterval
    var left: TimeInterval
    var right: TimeInterval
    var startedAt: Date?
    /// The side the parent should start on next (opposite of the last side used).
    var suggestedSide: Side?
    /// When the previous feed ended and on which side, for the "not started" header.
    var lastFeedEnded: Date?
    var lastFeedSide: Side?

    init(session: SessionSnapshot?, lastCompleted: SessionSnapshot?, suggestedSide: Side?, now: Date) {
        if let session, session.status != .completed {
            switch session.status {
            case .active:
                phase = .active(session.openSegment?.side ?? session.lastSide ?? .left)
            default:
                phase = .paused(lastSide: session.lastSide)
            }
            total = session.feedingDuration(at: now)
            left = session.duration(on: .left, at: now)
            right = session.duration(on: .right, at: now)
            startedAt = session.startedAt
            self.suggestedSide = nil
        } else {
            phase = .notStarted
            total = 0
            left = 0
            right = 0
            startedAt = nil
            self.suggestedSide = suggestedSide
        }
        lastFeedEnded = lastCompleted?.endedAt
        lastFeedSide = lastCompleted?.lastSide
    }

    var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    var activeSide: Side? {
        if case .active(let side) = phase { return side }
        return nil
    }

    func elapsed(on side: Side) -> TimeInterval {
        side == .left ? left : right
    }

    /// How each side button should present itself.
    func mode(for side: Side) -> SideButton.Mode {
        switch phase {
        case .notStarted:
            .start(suggested: suggestedSide == side)
        case .active(let running):
            running == side ? .active : .switchTo
        case .paused(let last):
            .resumeHere(wasLast: last == side)
        }
    }
}
