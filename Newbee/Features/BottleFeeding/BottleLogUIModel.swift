import Foundation
import NewbeeKit
import Observation

/// View model for bottle logging: presents the Log Bottle sheet (new or edit), saves and deletes
/// through `BottleLog`, offers undo, and keeps today's totals for Home and the latest few bottles.
///
/// It's in the SwiftUI environment, so any screen can call `presentNew()` or
/// `presentEdit(sessionID:)`; `RootView` hosts the sheet and the undo toast.
@MainActor
@Observable
final class BottleLogUIModel {
    /// What the sheet is editing. A new value presents the sheet.
    struct EditorRequest: Identifiable, Equatable {
        let id = UUID()
        var draft: BottleDraft
    }

    /// "Bottle saved · 90 mL formula  [Undo]".
    struct Toast: Identifiable, Equatable {
        enum UndoAction: Equatable {
            case save(BottleLog.SaveResult)
            case delete(BottleEntry)
        }

        let id = UUID()
        var message: String
        var undo: UndoAction
    }

    @ObservationIgnored let log: BottleLog
    let preferences: AppPreferences
    /// Called after every save, delete or undo (reminders count from the last feed).
    @ObservationIgnored private let onChange: @MainActor () -> Void

    var editor: EditorRequest?
    var toast: Toast?
    var errorMessage: String?
    private(set) var recent: [BottleEntry] = []
    private(set) var today = BottleDaySummary(entries: [])
    /// Changes on every event that should produce a haptic.
    private(set) var feedback: FeedbackEvent?

    /// How many recent bottles `recent` keeps.
    static let recentLimit = 3

    init(log: BottleLog, preferences: AppPreferences, onChange: @escaping @MainActor () -> Void = {}) {
        self.log = log
        self.preferences = preferences
        self.onChange = onChange
        refresh()
    }

    var unit: VolumeUnit { preferences.volumeUnit }

    var presets: [BottleAmount] {
        BottlePresets.amounts(storedML: preferences.bottlePresetsML, unit: unit, rules: log.rules)
    }

    // MARK: - Presentation

    /// Opens the sheet on a new bottle at `time` (default: now).
    func presentNew(at time: Date? = nil) {
        editor = EditorRequest(draft: log.newDraft(unit: unit, at: time))
    }

    /// Opens the sheet on an existing bottle feed (for example from a History row).
    func presentEdit(sessionID: UUID) {
        do {
            if let draft = try log.editDraft(id: sessionID) {
                editor = EditorRequest(draft: draft)
            } else {
                errorMessage = String(localized: "That bottle feed no longer exists.")
                refresh()
            }
        } catch {
            fail(error)
        }
    }

    func problems(with draft: BottleDraft) -> [BottleValidationError] {
        log.problems(with: draft)
    }

    // MARK: - Commands

    /// Saves the draft. Returns whether it was saved, so the sheet knows to close.
    @discardableResult
    func save(_ draft: BottleDraft) -> Bool {
        do {
            let result = try log.save(draft)
            preferences.volumeUnit = draft.amount.unit
            editor = nil
            feedback = FeedbackEvent(kind: .success)
            let what = Self.describe(result.saved)
            toast = Toast(
                message: result.previous == nil
                    ? String(localized: "Bottle saved · \(what)")
                    : String(localized: "Bottle updated · \(what)"),
                undo: .save(result)
            )
            refresh()
            onChange()
            return true
        } catch let problem as BottleValidationError {
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
            toast = Toast(message: String(localized: "Bottle deleted"), undo: .delete(deleted))
            refresh()
            onChange()
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
            onChange()
        } catch {
            fail(error)
        }
    }

    func dismissToast(id: Toast.ID) {
        if toast?.id == id { toast = nil }
    }

    /// Re-reads the recent list and today's totals from the store.
    func refresh() {
        do {
            recent = try log.recent(limit: Self.recentLimit)
            today = try log.summary(forDayContaining: log.clock.now)
        } catch {
            recent = []
            today = BottleDaySummary(entries: [])
        }
    }

    // MARK: - Formatting

    /// "90 mL formula", in the unit it was entered in.
    static func describe(_ entry: BottleEntry) -> String {
        "\(entry.enteredAmount.formatted) \(entry.contents.title.lowercased())"
    }

    /// "None today", "Today: 1 bottle · 120 mL" or "Today: 3 bottles · 270 mL".
    var todayLine: String {
        if today.isEmpty { return String(localized: "None today") }
        let total = formatted(ml: today.totalML)
        return today.count == 1
            ? String(localized: "Today: 1 bottle · \(total)")
            : String(localized: "Today: \(today.count) bottles · \(total)")
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

extension BottleContents {
    var title: String {
        switch self {
        case .breastMilk: String(localized: "Breast milk")
        case .formula: String(localized: "Formula")
        case .other: String(localized: "Other")
        }
    }
}

extension BottleValidationError {
    /// Shown under the form and in the error alert.
    var message: String {
        switch self {
        case .amountNotPositive:
            String(localized: "Enter an amount.")
        case .amountTooLarge(let maximumML):
            String(localized: "That's more than \(Int(maximumML)) mL. Check the amount and unit.")
        case .startInFuture:
            String(localized: "The time can't be in the future.")
        case .durationNotPositive:
            String(localized: "Duration must be at least a minute.")
        case .durationTooLong(let maximumSeconds):
            String(localized: "Duration can't be more than \(Int(maximumSeconds / 3600)) hours.")
        case .endInFuture:
            String(localized: "This feed would end in the future. Move the time earlier or shorten it.")
        }
    }
}
