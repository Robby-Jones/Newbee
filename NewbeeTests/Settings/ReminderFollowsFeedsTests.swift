import Foundation
import NewbeeKit
import Testing
@testable import Newbee

/// The feed reminder counts from the latest feed, however that feed got into the log: timed,
/// added or edited by hand, a bottle from Home, History or Calendar, or a feed from the other
/// parent's phone. A reminder that already fired comes off the Lock Screen once a newer feed is
/// logged.
@MainActor
@Suite("Feed reminder follows the latest feed")
struct ReminderFollowsFeedsTests {
    let clock = TestClock()
    let notifications = FakeNotificationClient()
    let interval: TimeInterval = 3 * 3600

    func makeDependencies() throws -> AppDependencies {
        let defaults = try #require(UserDefaults(suiteName: "NewbeeTests.\(UUID().uuidString)"))
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, notifications: notifications, defaults: defaults)
        dependencies.preferences.reminders.isEnabled = true
        return dependencies
    }

    var feedDueID: String { PlannedReminder.identifier(for: .feedDue) }
    var stillFeedingID: String { PlannedReminder.identifier(for: .stillFeeding) }

    func feedDue() async -> Date? {
        await notifications.pending[feedDueID]?.fireDate
    }

    /// Times a 20 minute breastfeed starting now. Returns when it started.
    func timeABreastfeed(_ dependencies: AppDependencies) async throws -> Date {
        let start = clock.now
        try dependencies.sessionManager.start(side: .left)
        clock.advance(by: 20 * 60)
        _ = try dependencies.sessionManager.end()
        await dependencies.sessionManager.waitForPendingEffects()
        return start
    }

    func logBottle(_ dependencies: AppDependencies, at time: Date? = nil) async throws -> BottleEntry {
        let draft = dependencies.bottleLog.newDraft(unit: .fluidOunces, at: time)
        let bottle = try dependencies.bottleLog.save(draft).saved
        await dependencies.bottlesDidChange(logged: bottle.id)
        return bottle
    }

    // MARK: - Bottles

    /// The report: a breastfeed at 5:22 PM, a bottle at 8:11 PM, and the reminder still fired at
    /// 8:22 PM. It must move to 3 h after the bottle.
    @Test func aBottleMovesTheReminderPastTheBreastfeedBeforeIt() async throws {
        let dependencies = try makeDependencies()
        let breastStart = try await timeABreastfeed(dependencies)
        #expect(await feedDue() == breastStart.addingTimeInterval(interval))

        clock.advance(by: 2 * 3600 + 29 * 60)
        let bottle = try await logBottle(dependencies)
        #expect(await feedDue() == bottle.startedAt.addingTimeInterval(interval))
        #expect(dependencies.reminders.pending.map(\.anchor) == [bottle.startedAt])
    }

    @Test func editingOrDeletingTheBottleMovesTheReminderAgain() async throws {
        let dependencies = try makeDependencies()
        let breastStart = try await timeABreastfeed(dependencies)
        clock.advance(by: 2 * 3600)
        let bottle = try await logBottle(dependencies)

        // Set back to 30 min earlier (History, Calendar or the bottle sheet).
        var draft = try #require(try dependencies.bottleLog.editDraft(id: bottle.id))
        draft.startedAt = bottle.startedAt.addingTimeInterval(-30 * 60)
        _ = try dependencies.bottleLog.save(draft)
        await dependencies.bottlesDidChange()
        #expect(await feedDue() == draft.startedAt.addingTimeInterval(interval))

        // Deleted: the breastfeed is the last feed again.
        _ = try dependencies.bottleLog.delete(id: bottle.id)
        await dependencies.bottlesDidChange()
        #expect(await feedDue() == breastStart.addingTimeInterval(interval))
    }

    /// The bottle sheet tells the app about every save, edit, delete and undo.
    @Test func theBottleSheetReportsEveryChange() throws {
        let dependencies = try makeDependencies()
        var changes: [UUID?] = []
        let model = BottleLogUIModel(log: dependencies.bottleLog, preferences: dependencies.preferences) { changes.append($0) }

        #expect(model.save(dependencies.bottleLog.newDraft(unit: .milliliters)))
        let saved = try #require(model.recent.first)
        #expect(changes == [saved.id])

        var edit = try #require(try dependencies.bottleLog.editDraft(id: saved.id))
        clock.advance(by: 60)
        edit.startedAt = clock.now.addingTimeInterval(-10 * 60)
        #expect(model.save(edit))
        model.delete(id: saved.id)
        model.undo()
        #expect(changes == [saved.id, nil, nil, nil])
    }

    // MARK: - Breastfeeds added, edited or deleted by hand

    @Test func aBreastfeedAddedEditedOrDeletedByHandMovesTheReminder() async throws {
        let dependencies = try makeDependencies()
        let manager = dependencies.sessionManager
        let bottle = try await logBottle(dependencies)

        clock.advance(by: 2 * 3600)
        let start = clock.now.addingTimeInterval(-30 * 60)
        let added = SessionSnapshot(
            status: .completed,
            segments: [Segment(side: .right, start: start, end: start.addingTimeInterval(15 * 60))],
            startedAt: start,
            endedAt: start.addingTimeInterval(15 * 60),
            revision: 1,
            source: .manual
        )
        try manager.addFeed(added)
        await manager.waitForPendingEffects()
        #expect(await feedDue() == start.addingTimeInterval(interval))

        // Edited to start 10 min later.
        let stored = try #require(manager.lastCompletedSession)
        var edited = stored
        edited.startedAt = start.addingTimeInterval(10 * 60)
        edited.segments = [Segment(side: .right, start: edited.startedAt, end: start.addingTimeInterval(15 * 60))]
        try manager.saveEdit(edited)
        await manager.waitForPendingEffects()
        #expect(await feedDue() == edited.startedAt.addingTimeInterval(interval))

        // Deleted: the bottle is the last feed again.
        _ = try manager.deleteCompleted(sessionID: added.id)
        await manager.waitForPendingEffects()
        #expect(await feedDue() == bottle.startedAt.addingTimeInterval(interval))
    }

    // MARK: - The other parent's phone

    /// A bottle the other parent logged arrives through iCloud: the store changes underneath the
    /// app, then the import hook runs.
    @Test func aBottleFromTheOtherPhoneMovesTheReminder() async throws {
        let dependencies = try makeDependencies()
        let breastStart = try await timeABreastfeed(dependencies)
        clock.advance(by: 2 * 3600 + 29 * 60)
        // Written straight to the store, as sync does, without telling the reminders.
        let bottle = try dependencies.bottleLog.save(dependencies.bottleLog.newDraft(unit: .fluidOunces)).saved
        #expect(await feedDue() == breastStart.addingTimeInterval(interval))

        await dependencies.cloudSyncDidImport()
        #expect(await feedDue() == bottle.startedAt.addingTimeInterval(interval))
    }

    // MARK: - Reminders that already fired

    /// The reminder fired, then the parent logged the bottle they gave before it, with its time
    /// set back. The old "It's been 3 h" comes off the Lock Screen.
    @Test func aFiredReminderIsClearedOnceANewerFeedIsLogged() async throws {
        let dependencies = try makeDependencies()
        let breastStart = try await timeABreastfeed(dependencies)
        clock.advance(by: interval - 20 * 60 + 60)
        await notifications.markDelivered(feedDueID)
        #expect(await notifications.delivered[feedDueID]?.anchor == breastStart)

        // Nothing newer yet: a pass (the app coming forward) leaves it there.
        await dependencies.reminders.reschedule()
        #expect(await notifications.delivered[feedDueID] != nil)

        let bottle = try await logBottle(dependencies, at: clock.now.addingTimeInterval(-11 * 60))
        #expect(await notifications.delivered[feedDueID] == nil)
        #expect(await feedDue() == bottle.startedAt.addingTimeInterval(interval))
    }

    @Test func aFiredStillFeedingCheckIsClearedOnceTheFeedEnds() async throws {
        let dependencies = try makeDependencies()
        let manager = dependencies.sessionManager
        try manager.start(side: .left)
        await manager.waitForPendingEffects()
        clock.advance(by: 46 * 60)
        await notifications.markDelivered(stillFeedingID)

        _ = try manager.end()
        await manager.waitForPendingEffects()
        #expect(await notifications.delivered[stillFeedingID] == nil)
    }
}
