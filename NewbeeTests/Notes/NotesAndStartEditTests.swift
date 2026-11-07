import Foundation
import NewbeeKit
import Testing
@testable import Newbee

@MainActor
@Suite("Note tags")
struct NoteTagTests {
    @Test func tappingATagAddsItWithASeparator() {
        #expect(NotesEditor.toggling("Sleepy", in: "") == "Sleepy")
        #expect(NotesEditor.toggling("Fussy", in: "Sleepy") == "Sleepy, Fussy")
        #expect(NotesEditor.toggling("Spit up", in: "Fed well.") == "Fed well. Spit up")
    }

    @Test func tappingASelectedTagRemovesItAndTidiesUp() {
        #expect(NotesEditor.toggling("Sleepy", in: "Sleepy, Fussy") == "Fussy")
        #expect(NotesEditor.toggling("Fussy", in: "Sleepy, Fussy") == "Sleepy")
        #expect(NotesEditor.toggling("Fussy", in: "Sleepy, Fussy, Hiccups") == "Sleepy, Hiccups")
        #expect(NotesEditor.contains("good latch", in: "Good latch today"))
    }
}

@MainActor
@Suite("Timer notes and start time")
struct TimerNoteAndStartTests {
    let clock = ManualNow()
    let controller: PreviewSessionController
    let model: FeedingSessionUIModel

    init() {
        let clock = clock
        controller = PreviewSessionController(now: { clock.date })
        model = FeedingSessionUIModel(controller: controller)
    }

    @Test func noteAddedOnFeedSavedIsStoredOnThatFeed() throws {
        model.tapSide(.left)
        clock.advance(10 * 60)
        model.endSession()
        let id = try #require(model.completedSummary?.id)

        model.saveNote("Sleepy, short latch", sessionID: id)

        #expect(controller.lastCompletedSession?.notes == "Sleepy, short latch")
        #expect(model.completedSummary?.notes == "Sleepy, short latch")
        #expect(controller.log.last == "saveEdit")
    }

    @Test func anUnchangedNoteIsNotSaved() throws {
        model.tapSide(.right)
        clock.advance(60)
        model.endSession()
        let id = try #require(model.completedSummary?.id)

        model.saveNote("", sessionID: id)

        #expect(!controller.log.contains("saveEdit"))
    }

    @Test func editStartMovesTheRunningFeedsStart() throws {
        let started = clock.date
        model.tapSide(.left)
        clock.advance(60)
        #expect(model.latestStart(at: clock.date) == started.addingTimeInterval(60))

        let earlier = started.addingTimeInterval(-5 * 60)
        model.editStart(to: earlier)

        #expect(controller.activeSession?.startedAt == earlier)
        #expect(controller.log.last == "adjustStart")
    }
}
