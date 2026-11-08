import Foundation
import NewbeeKit
@testable import NewbeeShared

typealias State = FeedingActivityAttributes.ContentState

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let otherSessionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let bottleID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
let otherBottleID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

func minutes(_ m: Double) -> TimeInterval { m * 60 }

/// Left 12 min from t0, then right running since t0+12m.
func activeOnRight(revision: Int = 2) -> SessionSnapshot {
    SessionSnapshot(
        id: sessionID,
        status: .active,
        segments: [
            Segment(side: .left, start: t0, end: t0 + minutes(12)),
            Segment(side: .right, start: t0 + minutes(12)),
        ],
        startedAt: t0,
        revision: revision
    )
}

/// Left 12, right 5, paused at t0+17m.
func pausedAfterRight(revision: Int = 3) -> SessionSnapshot {
    SessionSnapshot(
        id: sessionID,
        status: .paused,
        segments: [
            Segment(side: .left, start: t0, end: t0 + minutes(12)),
            Segment(side: .right, start: t0 + minutes(12), end: t0 + minutes(17)),
        ],
        startedAt: t0,
        revision: revision
    )
}

/// The guide's example: left 12, right 9, ended at t0+21m.
func completedSpecExample(revision: Int = 3) -> SessionSnapshot {
    SessionSnapshot(
        id: sessionID,
        status: .completed,
        segments: [
            Segment(side: .left, start: t0, end: t0 + minutes(12)),
            Segment(side: .right, start: t0 + minutes(12), end: t0 + minutes(21)),
        ],
        startedAt: t0,
        endedAt: t0 + minutes(21),
        revision: revision
    )
}

func record(
    _ id: String,
    session: UUID = sessionID,
    state: State,
    phase: LiveActivityRecord.Phase = .live
) -> LiveActivityRecord {
    LiveActivityRecord(id: id, sessionID: session, state: state, phase: phase)
}
