import Foundation
import NewbeeKit
import NewbeeShared

// Integration of the session engine and the Live Activity (docs/LIVE_ACTIVITIES.md §8).

/// Lock Screen and Dynamic Island buttons reach the single session manager through
/// `LiveActivityIntentRouter`. `applyRemote` ignores a stale session id and always re-syncs the
/// Live Activity before returning.
extension FeedingSessionManager: @retroactive LiveActivityCommandHandling {
    public func handleLiveActivityCommand(_ command: LiveActivityCommand, sessionID: UUID) async {
        if let engineCommand = SessionCommand(command) {
            await applyRemote(engineCommand, sessionID: sessionID)
        } else if case .start(let side) = command {
            // From the since-last-feed state: there is no running session for the id to name.
            await applyRemoteStart(side: side)
        }
    }
}

extension SessionCommand {
    /// The engine command for a button on a running feed, or `nil` for Start, which begins a new
    /// feed instead of changing the one the activity names.
    init?(_ command: LiveActivityCommand) {
        switch command {
        case .switchTo(let side): self = .switchTo(side)
        case .pause: self = .pause
        case .resume: self = .resume
        case .end: self = .end
        case .start: return nil
        }
    }
}

/// The manager drives the coordinator after every saved change.
extension LiveActivityCoordinator: LiveActivitySyncing {}
