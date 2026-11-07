import Foundation
import NewbeeKit

/// A command sent from a Lock Screen or Dynamic Island button.
///
/// Commands carry a target state ("switch to right"), never a toggle, so replaying one is
/// harmless (docs/TIMER_ENGINE.md §3).
public enum LiveActivityCommand: Hashable, Sendable {
    case switchTo(Side)
    case pause
    case resume
    case end
}

/// Implemented by the app's `FeedingSessionManager`, the single owner of the active session.
///
/// Contract:
/// - If `sessionID` is not the active session, ignore the command (it came from a stale
///   activity), but still sync the Live Activity so the stale one is ended.
/// - Otherwise apply the command through the session engine, save, and only then sync the
///   Live Activity, awaiting it before returning.
/// - Duplicate or no-op commands must not throw.
@MainActor
public protocol LiveActivityCommandHandling: AnyObject {
    func handleLiveActivityCommand(_ command: LiveActivityCommand, sessionID: UUID) async
}

/// Connects the App Intents behind Live Activity buttons to the app's session manager.
///
/// Live Activity intents run in the app's process (launched in the background if needed), so
/// the app registers its manager here from `App.init`. The widget extension never registers a
/// handler: it only renders buttons that carry the intents.
@MainActor
public enum LiveActivityIntentRouter {
    private static weak var handler: (any LiveActivityCommandHandling)?

    public static func register(_ handler: any LiveActivityCommandHandling) {
        self.handler = handler
    }

    public static var isRegistered: Bool { handler != nil }

    /// Forwards the command. Returns `false` if no handler was registered (a wiring bug, which
    /// the app's tests guard against), so the intent can log it instead of crashing.
    @discardableResult
    public static func route(_ command: LiveActivityCommand, sessionID: UUID) async -> Bool {
        guard let handler else { return false }
        await handler.handleLiveActivityCommand(command, sessionID: sessionID)
        return true
    }
}
