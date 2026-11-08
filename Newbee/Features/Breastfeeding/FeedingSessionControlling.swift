import Foundation
import NewbeeKit

/// What the breastfeeding UI needs from the session manager (docs/ARCHITECTURE.md §3).
///
/// The timer screen, the Active Session Pill and the recovery sheet bind to this protocol rather
/// than to the concrete `FeedingSessionManager`, so views stay free of timing logic and can be
/// previewed and tested with an in-memory stand-in. All timing comes from `SessionSnapshot`
/// timestamps; the UI only re-renders them.
@MainActor
protocol FeedingSessionControlling: AnyObject, Observable {
    /// The active or paused session, or `nil` when no feed is running ("Not started").
    var activeSession: SessionSnapshot? { get }

    /// The most recently completed breastfeeding session, used for "last side" and the
    /// suggested next side.
    var lastCompletedSession: SessionSnapshot? { get }

    /// The side to start on next: the opposite of the side used last.
    var suggestedNextSide: Side { get }

    /// Set by recovery when a running session looks wrong (forgotten timer, clock change).
    /// While non-nil the UI shows the recovery sheet, which can't be swiped away.
    var recoveryPrompt: RecoveryPrompt? { get }

    func start(side: Side) throws
    /// Switches to `side`. While paused this resumes on `side`. Switching to the running side is a no-op.
    func switchSide(to side: Side) throws
    func pause() throws
    func resume() throws

    /// Corrects the start of the active session (recovery's "fix start time" after a clock change).
    func adjustStart(to date: Date) throws

    /// Ends the active session at `date` (`nil` means now).
    /// - Returns: the session as it was *before* ending, so the UI can offer undo via `restore(_:)`.
    @discardableResult
    func end(at date: Date?) throws -> SessionSnapshot

    /// Removes the active session.
    /// - Returns: the discarded session, so the UI can offer undo via `restore(_:)`.
    @discardableResult
    func discardActive() throws -> SessionSnapshot

    /// Undo: writes `snapshot` back (re-opens an ended session or re-inserts a discarded one).
    func restore(_ snapshot: SessionSnapshot) throws

    /// Settings' "Refresh Live Activity": replaces the Live Activity with a fresh one for the
    /// running feed or the since-last-feed count, bringing it back if it was swiped away.
    func refreshLiveActivity() async

    /// Inserts a new finished feed entered by hand. If it is the latest feed, the Live
    /// Activity's since-last-feed count comes back even if the parent swiped it away.
    func addFeed(_ snapshot: SessionSnapshot) throws

    /// Saves a hand-edited finished feed (History's Edit). Throws if the times break the session rules.
    func saveEdit(_ edited: SessionSnapshot) throws

    /// Deletes a finished feed (History's Delete).
    /// - Returns: the deleted session, so the UI can offer undo via `restore(_:)`.
    @discardableResult
    func deleteCompleted(sessionID: UUID) throws -> SessionSnapshot

    /// Recovery sheet's "Keep going": clears `recoveryPrompt` without changing the session.
    func dismissRecovery()
}

/// Errors thrown by the in-memory preview controller. The real manager throws `SessionEngineError`.
enum PreviewSessionError: Error, Equatable {
    case alreadyActive
    case noActiveSession
    case notFound
}
