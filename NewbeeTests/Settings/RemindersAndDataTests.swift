import CoreGraphics
import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// Records what the scheduler asks UserNotifications to do.
actor FakeNotificationClient: NotificationClient {
    var current: NotificationPermission
    var grantsOnRequest: Bool
    private(set) var pending: [String: ScheduledNotification] = [:]
    private(set) var requestCount = 0
    private(set) var removeAllCount = 0

    init(permission: NotificationPermission = .allowed, grantsOnRequest: Bool = true) {
        current = permission
        self.grantsOnRequest = grantsOnRequest
    }

    func permission() async -> NotificationPermission { current }

    func requestPermission() async -> Bool {
        requestCount += 1
        if current == .notDetermined { current = grantsOnRequest ? .allowed : .denied }
        return current == .allowed
    }

    func replace(identifiers: [String], with notifications: [ScheduledNotification]) async {
        for id in identifiers { pending[id] = nil }
        for notification in notifications { pending[notification.identifier] = notification }
    }

    func removeAll() async {
        removeAllCount += 1
        pending = [:]
    }
}

private func freshDefaults() -> UserDefaults {
    let name = "NewbeeTests.\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
}

@MainActor
@Suite("Reminders")
struct ReminderSchedulerTests {
    let clock = TestClock()
    let notifications = FakeNotificationClient()

    func makeDependencies() -> AppDependencies {
        AppDependencies(clock: clock, storage: .inMemory, notifications: notifications, defaults: freshDefaults())
    }

    var feedDueID: String { PlannedReminder.identifier(for: .feedDue) }
    var stillFeedingID: String { PlannedReminder.identifier(for: .stillFeeding) }

    @Test func endingAFeedSchedulesTheNextReminder() async throws {
        let dependencies = makeDependencies()
        dependencies.preferences.reminders.isEnabled = true
        let manager = dependencies.sessionManager
        let start = clock.now
        try manager.start(side: .left)
        await manager.waitForPendingEffects()
        // While feeding, only the "Still feeding?" check is pending.
        #expect(await notifications.pending[stillFeedingID]?.fireDate == start.addingTimeInterval(45 * 60))
        #expect(await notifications.pending[feedDueID] == nil)

        clock.advance(by: 20 * 60)
        _ = try manager.end()
        await manager.waitForPendingEffects()
        let due = try #require(await notifications.pending[feedDueID])
        #expect(due.fireDate == start.addingTimeInterval(3 * 3600))
        #expect(due.title == "Feeding reminder")
        #expect(await notifications.pending[stillFeedingID] == nil)
    }

    @Test func switchingSidesMovesTheStillFeedingCheck() async throws {
        let dependencies = makeDependencies()
        let manager = dependencies.sessionManager
        try manager.start(side: .left)
        clock.advance(by: 10 * 60)
        try manager.switchSide(to: .right)
        await manager.waitForPendingEffects()
        let still = try #require(await notifications.pending[stillFeedingID])
        #expect(still.fireDate == clock.now.addingTimeInterval(45 * 60))
        #expect(still.body.contains("right"))
    }

    @Test func aBottleCountsAsTheLastFeed() async throws {
        let dependencies = makeDependencies()
        dependencies.preferences.reminders.isEnabled = true
        let draft = dependencies.bottleLog.newDraft(unit: .milliliters)
        try dependencies.bottleLog.save(draft)
        await dependencies.reminders.reschedule()
        #expect(await notifications.pending[feedDueID]?.fireDate == draft.startedAt.addingTimeInterval(3 * 3600))
    }

    @Test func nothingIsScheduledWithoutPermission() async throws {
        let denied = FakeNotificationClient(permission: .denied)
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, notifications: denied, defaults: freshDefaults())
        dependencies.preferences.reminders.isEnabled = true
        try dependencies.sessionManager.start(side: .left)
        await dependencies.sessionManager.waitForPendingEffects()
        #expect(await denied.pending.isEmpty)
        #expect(dependencies.reminders.permission == .denied)
    }

    @Test func requestingPermissionSchedulesRightAway() async throws {
        let undecided = FakeNotificationClient(permission: .notDetermined)
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, notifications: undecided, defaults: freshDefaults())
        try dependencies.sessionManager.start(side: .left)
        await dependencies.sessionManager.waitForPendingEffects()
        #expect(await undecided.pending.isEmpty)

        #expect(await dependencies.reminders.requestPermission())
        #expect(dependencies.reminders.permission == .allowed)
        #expect(await undecided.pending[stillFeedingID] != nil)
        #expect(dependencies.reminders.pending.map(\.kind) == [.stillFeeding])
    }

    @Test func wordingIsCalmAndSpecific() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let due = ReminderScheduler.notification(
            for: PlannedReminder(kind: .feedDue, fireDate: anchor.addingTimeInterval(3 * 3600), anchor: anchor),
            basis: .start, interval: 3 * 3600
        )
        #expect(due.body.hasPrefix("It's been 3 h."))
        let paused = ReminderScheduler.notification(
            for: PlannedReminder(kind: .stillFeeding, fireDate: anchor.addingTimeInterval(30 * 60), anchor: anchor),
            basis: .start, interval: 3 * 3600
        )
        #expect(paused.title == "Still feeding?")
        #expect(paused.body.contains("paused for 30 min"))
    }
}

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    @Test func reminderSettingsPersist() {
        let defaults = freshDefaults()
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.reminders == ReminderSettings())
        preferences.reminders = ReminderSettings(
            isEnabled: true, interval: 150 * 60, basis: .end,
            quietHours: QuietHours(startMinute: 21 * 60 + 30, endMinute: 5 * 60),
            stillFeedingEnabled: false, stillFeedingThreshold: 30 * 60
        )
        preferences.appearance = .dark
        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.reminders == preferences.reminders)
        #expect(reloaded.appearance == .dark)
    }

    @Test func resetKeepsAppearance() {
        let defaults = freshDefaults()
        let preferences = AppPreferences(defaults: defaults, locale: Locale(identifier: "en_GB"))
        preferences.volumeUnit = .fluidOunces
        preferences.bottlePresetsML = [50, 100, 150]
        preferences.reminders.isEnabled = true
        preferences.appearance = .light
        preferences.resetToDefaults()
        #expect(preferences.volumeUnit == .milliliters)
        #expect(preferences.bottlePresetsML == nil)
        #expect(preferences.reminders == ReminderSettings())
        #expect(preferences.appearance == .light)
        let reloaded = AppPreferences(defaults: defaults, locale: Locale(identifier: "en_GB"))
        #expect(reloaded.reminders == ReminderSettings())
        #expect(reloaded.appearance == .light)
    }
}

@MainActor
@Suite("Export and delete all")
struct DataManagementTests {
    let clock = TestClock()

    @Test func exportWritesEveryFinishedFeed() throws {
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, notifications: FakeNotificationClient(), defaults: freshDefaults())
        let manager = dependencies.sessionManager
        try manager.start(side: .left)
        clock.advance(by: 12 * 60)
        _ = try manager.end()
        clock.advance(by: 60 * 60)
        try dependencies.bottleLog.save(dependencies.bottleLog.newDraft(unit: .milliliters))
        // A running feed isn't exported.
        try manager.start(side: .right)

        let url = try dependencies.exportCSV()
        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.split(separator: "\r\n")
        #expect(lines.count == 3)
        #expect(lines[1].contains(",breast,12.0,12.0,0.0,left,left,"))
        #expect(lines[2].contains(",bottle,"))
        #expect(url.lastPathComponent.hasSuffix(".csv"))
    }

    @Test func pdfReportHasASummaryPageThenTheLog() throws {
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, notifications: FakeNotificationClient(), defaults: freshDefaults())
        let context = try #require(dependencies.modelContainer?.mainContext)
        context.insert(Baby(name: "Juniper"))
        try context.save()
        let manager = dependencies.sessionManager
        try manager.start(side: .left)
        clock.advance(by: 12 * 60)
        _ = try manager.end()
        clock.advance(by: 60 * 60)
        try dependencies.bottleLog.save(dependencies.bottleLog.newDraft(unit: .milliliters))
        clock.advance(by: 60 * 60)
        _ = try dependencies.pumpLog.save(dependencies.pumpLog.newDraft(unit: .milliliters))

        let url = try dependencies.exportPDF(range: .lastDays(7))
        #expect(url.pathExtension == "pdf")
        #expect(url.lastPathComponent.hasPrefix("Newbee feeding report "))
        let document = try #require(CGPDFDocument(url as CFURL))
        #expect(document.numberOfPages == 2)
        let box = try #require(document.page(at: 1)?.getBoxRect(.mediaBox))
        #expect(box.size == CGSize(width: 612, height: 792))
    }

    @Test func emptyPDFReportIsOneSummaryPage() throws {
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, notifications: FakeNotificationClient(), defaults: freshDefaults())
        let url = try dependencies.exportPDF(range: .lastDays(14))
        let document = try #require(CGPDFDocument(url as CFURL))
        #expect(document.numberOfPages == 1)
    }

    @Test func longLogsFlowOntoMorePages() throws {
        let report = FeedReport(
            feeds: (0..<120).map { index in
                let start = clock.now.addingTimeInterval(-Double(index) * 2 * 3600)
                return FeedEntry(id: UUID(), start: start, end: start.addingTimeInterval(900),
                                 details: .breast(left: 600, right: 300, firstSide: .left, lastSide: .right),
                                 notes: index.isMultiple(of: 5) ? "Fussy at the start, then settled and fed well." : "")
            },
            pumps: [],
            interval: FeedReportRange.lastDays(11).interval(now: clock.now)
        )
        let pages = FeedReportPDF.paginate(report, header: FeedReportPDF.Header(), calendar: .current)
        #expect(pages.count >= 3)
        // Every feed in the range appears exactly once, and no page starts with a day heading
        // that has nothing under it.
        let rows = pages.flatMap { $0 }.filter { if case .item = $0 { true } else { false } }
        #expect(rows.count == report.feedCount)
        for page in pages {
            if case .day = page.last { Issue.record("A page ends with a day heading") }
        }
    }

    @Test func deleteAllRemovesEverythingAndCancelsReminders() async throws {
        let notifications = FakeNotificationClient()
        let dependencies = AppDependencies(clock: clock, storage: .inMemory, notifications: notifications, defaults: freshDefaults())
        let context = try #require(dependencies.modelContainer?.mainContext)
        context.insert(Baby(name: "Juniper"))
        try context.save()
        dependencies.preferences.reminders.isEnabled = true
        dependencies.preferences.appearance = .dark
        let manager = dependencies.sessionManager
        try manager.start(side: .left)
        clock.advance(by: 600)
        _ = try manager.end()
        try dependencies.bottleLog.save(dependencies.bottleLog.newDraft(unit: .milliliters))
        try manager.start(side: .right)
        await manager.waitForPendingEffects()
        let pendingBefore = await notifications.pending
        #expect(!pendingBefore.isEmpty)

        try await dependencies.deleteAllData()

        #expect(try context.fetchCount(FetchDescriptor<FeedingSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FeedingSegment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BottleDetails>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Baby>()) == 0)
        #expect(manager.activeSession == nil)
        #expect(manager.lastCompletedSession == nil)
        #expect(await notifications.pending.isEmpty)
        #expect(await notifications.removeAllCount == 1)
        #expect(dependencies.preferences.reminders.isEnabled == false)
        #expect(dependencies.preferences.appearance == .dark)
    }
}
