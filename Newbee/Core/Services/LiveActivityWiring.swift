import Foundation
import NewbeeKit
import NewbeeShared

// Integration of the session engine and the Live Activity (docs/LIVE_ACTIVITIES.md §8).

/// Lock Screen and Dynamic Island buttons reach the single session manager through
/// `LiveActivityIntentRouter`. `applyRemote` ignores a stale session id and always re-syncs the
/// Live Activity before returning.
extension FeedingSessionManager: @retroactive LiveActivityCommandHandling {
    public func handleLiveActivityCommand(_ command: LiveActivityCommand, sessionID: UUID) async {
        await applyRemote(SessionCommand(command), sessionID: sessionID)
    }
}

extension SessionCommand {
    init(_ command: LiveActivityCommand) {
        switch command {
        case .switchTo(let side): self = .switchTo(side)
        case .pause: self = .pause
        case .resume: self = .resume
        case .end: self = .end
        }
    }
}

/// The manager drives the coordinator after every saved change.
extension LiveActivityCoordinator: LiveActivitySyncing {}
