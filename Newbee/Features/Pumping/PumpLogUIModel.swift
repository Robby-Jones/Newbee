import Foundation
import NewbeeKit
import Observation

/// View model for pumping: presents the Log Pumping sheet (new or edit), saves and deletes
/// through `PumpLog`, offers undo, and keeps today's totals and the latest session for Home.
///
/// It's in the SwiftUI environment, so any screen can call `presentNew()` or
/// `presentEdit(sessionID:)`; `RootView` hosts the sheet and each tab hosts the undo toast.
@MainActor
@Observable
final class PumpLogUIModel {
    /// What the sheet is editing. A new value presents the sheet.
    struct EditorRequest: Identifiable, Equatable {
        let id = UUID()
        var draft: PumpDraft
    }

    /// "Pumping saved · 120 mL  [Undo]".
    struct Toast: Identifiable, Equatable {
        enum UndoAction: Equatable {
            case save(PumpLog.SaveResult)
            case delete(PumpEntry)
        }

        let id = UUID()
        var message: String
        var undo: UndoAction
    }

    @ObservationIgnored let log: PumpLog
    let preferences: AppPreferences

    var editor: EditorRequest?
    var toast: Toast?
    var errorMessage: String?
    private(set) var latest: PumpEntry?
    private(set) var today = PumpSummary(entries: [])
    /// Changes on every event that should produce a haptic.
    private(set) var feedback: FeedbackEvent?

    init(log: PumpLog, preferences: AppPreferences) {
        self.log = log
        self.preferences = preferences
        refresh()
    }

    /// Pumping shares the parent's volume unit with bottles.
    var unit: VolumeUnit { preferences.volumeUnit }

    // MARK: - Presentation

    func presentNew() {
        editor = EditorRequest(draft: log.newDraft(unit: unit))
    }

    /// Opens the sheet on an existing session (for example from a History row).
    func presentEdit(sessionID: UUID) {
        do {
            if let draft = try log.editDraft(id: sessionID) {
                editor = EditorRequest(draft: draft)
            } else {
                errorMessage = String(localized: "That pumping session no longer exists.")
                refresh()
            }
        } catch {
            fail(error)
        }
    }

    func problems(with draft: PumpDraft) -> [PumpValidationError] {
        log.problems(with: draft)
    }

    // MARK: - Commands

    /// Saves the draft. Returns whether it was saved, so the sheet knows to close.
    @discardableResult
    func save(_ draft: PumpDraft) -> Bool {
        do {
            let result = try log.save(draft)
            preferences.volumeUnit = draft.unit
            editor = nil
            feedback = FeedbackEvent(kind: .success)
            let what = result.saved.totalAmount.formatted
            toast = Toast(
                message: result.previous == nil
                    ? String(localized: "Pumping saved · \(what)")
                    : String(localized: "Pumping updated · \(what)"),
                undo: .save(result)
            )
            refresh()
            return true
        } catch let problem as PumpValidationError {
            feedback = FeedbackEvent(kind: .warning)
            errorMessage = problem.message
            return false
        } catch {
            fail(error)
            return false
        }
    }

    func delete(id: UUID) {
        do {
            guard let deleted = try log.delete(id: id) else { return }
            if editor?.draft.id == id { editor = nil }
            feedback = FeedbackEvent(kind: .light)
            toast = Toast(message: String(localized: "Pumping deleted"), undo: .delete(deleted))
            refresh()
        } catch {
            fail(error)
        }
    }

    func undo() {
        guard let toast else { return }
        self.toast = nil
        do {
            switch toast.undo {
            case .save(let result): try log.undo(result)
            case .delete(let entry): try log.restore(entry)
            }
            feedback = FeedbackEvent(kind: .light)
            refresh()
        } catch {
            fail(error)
        }
    }

    func dismissToast(id: Toast.ID) {
        if toast?.id == id { toast = nil }
    }

    /// Re-reads the latest session and today's totals from the store.
    func refresh() {
        do {
            latest = try log.recent(limit: 1).first
            today = try log.summary(forDayContaining: log.clock.now)
        } catch {
            latest = nil
            today = PumpSummary(entries: [])
        }
    }

    // MARK: - Formatting

    /// "None today", "Today: 1 session · 120 mL" or "Today: 3 sessions · 360 mL".
    var todayLine: String {
        if today.isEmpty { return String(localized: "None today") }
        let total = formatted(ml: today.totalML)
        return today.count == 1
            ? String(localized: "Today: 1 session · \(total)")
            : String(localized: "Today: \(today.count) sessions · \(total)")
    }

    /// A total in the parent's unit: "180 mL", "6 oz".
    func formatted(ml: Double) -> String {
        BottleAmount(milliliters: ml).converted(to: unit).formatted
    }

    private func fail(_ error: Error) {
        feedback = FeedbackEvent(kind: .warning)
        errorMessage = String(localized: "That didn't work. (\(error.localizedDescription))")
    }
}

extension PumpValidationError {
    /// Shown under the form and in the error alert.
    var message: String {
        switch self {
        case .amountNotPositive:
            String(localized: "Enter how much you pumped.")
        case .sideTooLarge(let side, let maximumML):
            String(localized: "\(side.title) is more than \(Int(maximumML)) mL. Check the amount and unit.")
        case .startInFuture:
            String(localized: "The start can't be in the future.")
        case .durationNotPositive:
            String(localized: "Duration must be at least a minute.")
        case .durationTooLong(let maximumSeconds):
            String(localized: "Duration can't be more than \(Int(maximumSeconds / 3600)) hours.")
        case .endInFuture:
            String(localized: "This session would end in the future. Move the start earlier or shorten it.")
        }
    }
}
