import Foundation
import NewbeeKit
import Observation

/// View model shared by the timer screen, the Active Session Pill, the recovery sheet and the
/// undo toast. It translates taps into session-manager commands and owns transient UI state
/// (presentation, toast, haptics). It holds no timing state of its own.
@MainActor
@Observable
final class FeedingSessionUIModel {
    let controller: any FeedingSessionControlling

    /// Whether the full-screen timer is showing. Dismissing it never affects the session.
    var isTimerPresented = false
    /// The session that was just ended from the timer screen, shown as a summary.
    var completedSummary: SessionSnapshot?
    var toast: UndoToast?
    /// A user-facing error from the last command, if any.
    var errorMessage: String?
    /// Changes on every event that should produce a haptic.
    private(set) var feedback: FeedbackEvent?

    init(controller: any FeedingSessionControlling) {
        self.controller = controller
    }

    var activeSession: SessionSnapshot? { controller.activeSession }
    var recoveryPrompt: RecoveryPrompt? { controller.recoveryPrompt }

    func display(at now: Date) -> BreastfeedingTimerDisplay {
        BreastfeedingTimerDisplay(
            session: controller.activeSession,
            lastCompleted: controller.lastCompletedSession,
            suggestedSide: controller.suggestedNextSide,
            now: now
        )
    }

    // MARK: - Presentation

    func openTimer() {
        completedSummary = nil
        isTimerPresented = true
    }

    func closeTimer() {
        isTimerPresented = false
        completedSummary = nil
    }

    // MARK: - Commands

    /// One tap on LEFT or RIGHT does the obvious thing for the current state:
    /// start, switch, resume on that side, or nothing if that side is already running.
    func tapSide(_ side: Side) {
        guard let session = controller.activeSession else {
            perform(.light) { try controller.start(side: side) }
            completedSummary = nil
            return
        }
        if session.status == .active, session.openSegment?.side == side {
            return
        }
        perform(.light) { try controller.switchSide(to: side) }
    }

    /// Starts a feed from outside the timer (Home) and shows the timer.
    func startFromHome(side: Side) {
        tapSide(side)
        openTimer()
    }

    func togglePause() {
        guard let session = controller.activeSession else { return }
        if session.status == .paused {
            perform(.light) { try controller.resume() }
        } else {
            perform(.light) { try controller.pause() }
        }
    }

    /// Ends the feed now, shows the summary and offers undo.
    func endSession() {
        guard controller.activeSession != nil else { return }
        do {
            let before = try controller.end(at: nil)
            completedSummary = controller.lastCompletedSession ?? before
            feedback = FeedbackEvent(kind: .success)
            let minutes = DurationText.short(completedSummary?.feedingDuration(at: completedSummary?.endedAt ?? .now) ?? 0)
            showUndo(String(localized: "Feed saved · \(minutes)"), restoring: before)
        } catch {
            fail(error)
        }
    }

    /// Discards the running feed, with undo.
    func discardSession() {
        guard controller.activeSession != nil else { return }
        do {
            let discarded = try controller.discardActive()
            completedSummary = nil
            isTimerPresented = false
            feedback = FeedbackEvent(kind: .light)
            showUndo(String(localized: "Feed discarded"), restoring: discarded)
        } catch {
            fail(error)
        }
    }

    // MARK: - Recovery

    func recoveryKeepGoing() {
        controller.dismissRecovery()
    }

    func recoveryEnd(at date: Date?) {
        do {
            let before = try controller.end(at: date)
            feedback = FeedbackEvent(kind: .success)
            showUndo(String(localized: "Feed saved"), restoring: before)
        } catch {
            fail(error)
        }
    }

    func recoveryDiscard() {
        discardSession()
    }

    /// Clock-change recovery: move the start to the time the monotonic clock implies.
    func recoveryFixStart(to date: Date) {
        perform(.light) { try controller.adjustStart(to: date) }
    }

    // MARK: - History

    /// Deletes a finished breastfeed, with undo. Bottles are deleted through `BottleLogUIModel`.
    func deleteFeed(id: UUID) {
        do {
            let deleted = try controller.deleteCompleted(sessionID: id)
            showUndo(String(localized: "Feed deleted"), restoring: deleted)
            errorMessage = nil
            feedback = FeedbackEvent(kind: .light)
        } catch {
            fail(error)
        }
    }

    /// Saves an edited finished breastfeed. Throws so the edit sheet can show the problem in place.
    func saveEdit(_ edited: SessionSnapshot) throws {
        try controller.saveEdit(edited)
        feedback = FeedbackEvent(kind: .success)
    }

    /// Timer's "Edit start", for a feed whose timer was started late (or early): moves the whole
    /// running feed so it started at `newStart`. Every timestamp shifts by the same amount, so the
    /// running side gains (or loses) the difference and finished sides keep their times.
    func editStart(to newStart: Date) {
        guard let session = controller.activeSession else { return }
        let reference = Self.adjustReference(of: session)
        let target = newStart.addingTimeInterval(reference.timeIntervalSince(session.startedAt))
        perform(.light) { try controller.adjustStart(to: target) }
    }

    /// The latest start "Edit start" allows: any later would put part of the feed in the future.
    func latestStart(at now: Date) -> Date? {
        guard let session = controller.activeSession else { return nil }
        return session.startedAt.addingTimeInterval(now.timeIntervalSince(Self.adjustReference(of: session)))
    }

    /// The timestamp `adjustStart(to:)` moves to the given date: the running segment's start, or
    /// the latest segment end of a paused feed (mirrors `FeedingSessionManager.adjustStart`).
    private static func adjustReference(of session: SessionSnapshot) -> Date {
        (session.status == .active ? session.openSegment?.start : nil)
            ?? session.segments.compactMap(\.end).max()
            ?? session.startedAt
    }

    /// Sets the note on the running feed or one that just ended (timer's "Add note", the Feed
    /// saved summary). Starts from the manager's current copy of the session, so a side switch
    /// made from the Lock Screen meanwhile isn't overwritten. Only the note changes, so the feed
    /// keeps its timer source.
    func saveNote(_ text: String, sessionID: UUID) {
        let current = [controller.activeSession, controller.lastCompletedSession, completedSummary]
            .compactMap { $0 }
            .first { $0.id == sessionID }
        guard var session = current, session.notes != text else { return }
        session.notes = text
        perform(.light) { try controller.saveEdit(session) }
        if completedSummary?.id == sessionID {
            completedSummary?.notes = text
        }
    }

    /// Adds a finished breastfeed entered by hand.
    func addManualFeed(_ session: SessionSnapshot) throws {
        try controller.restore(session)
        feedback = FeedbackEvent(kind: .success)
    }

    // MARK: - Undo

    func undo() {
        guard let toast else { return }
        self.toast = nil
        do {
            try controller.restore(toast.snapshot)
            completedSummary = nil
            feedback = FeedbackEvent(kind: .light)
        } catch {
            fail(error)
        }
    }

    func dismissToast(id: UndoToast.ID) {
        if toast?.id == id { toast = nil }
    }

    // MARK: - Helpers

    private func showUndo(_ message: String, restoring snapshot: SessionSnapshot) {
        toast = UndoToast(message: message, snapshot: snapshot)
    }

    private func perform(_ kind: FeedbackEvent.Kind, _ command: () throws -> Void) {
        do {
            try command()
            errorMessage = nil
            feedback = FeedbackEvent(kind: kind)
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        feedback = FeedbackEvent(kind: .warning)
        errorMessage = String(localized: "That didn't work. Your feed is still saved. (\(error.localizedDescription))")
    }
}

/// A short-lived "Undo" offer (6 s) after ending, discarding or deleting a feed.
struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    /// The state to write back if the user taps Undo.
    var snapshot: SessionSnapshot

    static let lifetime: Duration = .seconds(6)
}
