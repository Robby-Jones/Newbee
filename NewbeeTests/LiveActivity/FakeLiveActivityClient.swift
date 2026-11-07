import Foundation
import NewbeeShared
@testable import Newbee

/// In-memory stand-in for ActivityKit that records every call.
@MainActor
final class FakeLiveActivityClient: LiveActivityClient {
    enum Call: Equatable {
        case request(sessionID: UUID, revision: Int)
        case update(id: String, revision: Int)
        case end(id: String, final: FeedingActivityAttributes.ContentState.Status?, dismissal: LiveActivityDismissal)
    }

    var areActivitiesEnabled = true
    var refuseRequests = false
    var onUserDismissal: (@MainActor (UUID, Int) -> Void)?
    var onEnablementChange: (@MainActor (Bool) -> Void)?

    private(set) var calls: [Call] = []
    private(set) var activities: [LiveActivityRecord] = []
    private var nextID = 1

    struct Refused: Error {}

    func records() -> [LiveActivityRecord] { activities }

    func request(
        _ attributes: FeedingActivityAttributes,
        state: FeedingActivityAttributes.ContentState,
        staleDate: Date
    ) throws -> String {
        if refuseRequests { throw Refused() }
        let id = "activity-\(nextID)"
        nextID += 1
        activities.append(LiveActivityRecord(id: id, sessionID: attributes.sessionID, state: state, phase: .live))
        calls.append(.request(sessionID: attributes.sessionID, revision: state.revision))
        return id
    }

    func update(id: String, state: FeedingActivityAttributes.ContentState, staleDate: Date) async {
        await Task.yield() // ActivityKit suspends here; exposes interleaving bugs.
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].state = state
        calls.append(.update(id: id, revision: state.revision))
    }

    func end(id: String, finalState: FeedingActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async {
        await Task.yield()
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        if let finalState { activities[index].state = finalState }
        activities[index].phase = .finished
        calls.append(.end(id: id, final: finalState?.status, dismissal: dismissal))
    }

    // MARK: Simulated system events

    /// The device restarted or the 8-hour limit hit: activities are gone.
    func systemRemovesAll() {
        for index in activities.indices { activities[index].phase = .finished }
    }

    /// The parent swiped the activity away on the Lock Screen.
    func userDismisses(_ id: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].phase = .finished
        onUserDismissal?(activities[index].sessionID, activities[index].state.revision)
    }

    func clearCalls() { calls.removeAll() }
}
