import Foundation
import NewbeeKit
import Testing
@testable import NewbeeShared

@MainActor
final class RecordingHandler: LiveActivityCommandHandling {
    var received: [(LiveActivityCommand, UUID)] = []
    func handleLiveActivityCommand(_ command: LiveActivityCommand, sessionID: UUID) async {
        received.append((command, sessionID))
    }
}

@MainActor
@Suite("Intent routing", .serialized)
struct LiveActivityIntentRouterTests {
    @Test func forwardsCommandsToTheRegisteredHandler() async {
        let handler = RecordingHandler()
        LiveActivityIntentRouter.register(handler)
        #expect(LiveActivityIntentRouter.isRegistered)
        #expect(await LiveActivityIntentRouter.route(.switchTo(.left), sessionID: sessionID))
        #expect(await LiveActivityIntentRouter.route(.end, sessionID: sessionID))
        #expect(await LiveActivityIntentRouter.route(.start(.right), sessionID: sessionID))
        #expect(handler.received.map(\.0) == [.switchTo(.left), .end, .start(.right)])
        #expect(handler.received.allSatisfy { $0.1 == sessionID })
    }

    @Test func reportsAMissingHandlerInsteadOfCrashing() async {
        do {
            let handler = RecordingHandler()
            LiveActivityIntentRouter.register(handler)
        }
        // The router holds the handler weakly; the app keeps the manager alive.
        #expect(!LiveActivityIntentRouter.isRegistered)
        #expect(await LiveActivityIntentRouter.route(.pause, sessionID: sessionID) == false)
    }
}
