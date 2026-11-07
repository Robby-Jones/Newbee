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
        } else {
            await undoEnd(sessionID: sessionID)
        }
    }
}

extension SessionCommand {
    /// The engine command behind a button, or `nil` for Undo, which reopens a finished feed
    /// instead of changing a running one.
    init?(_ command: LiveActivityCommand) {
        switch command {
        case .switchTo(let side): self = .switchTo(side)
        case .pause: self = .pause
        case .resume: self = .resume
        case .end: self = .end
        case .undoEnd: return nil
        }
    }
}

/// The manager drives the coordinator after every saved change.
extension LiveActivityCoordinator: LiveActivitySyncing {}
