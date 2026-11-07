import Foundation
import Testing
@testable import NewbeeKit

/// Fixed calendar so day grouping doesn't depend on the machine running the tests.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-11-07 00:00 UTC.
private let midnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 7))!

private func at(_ hour: Double, dayOffset: Int = 0) -> Date {
    midnight.addingTimeInterval(Double(dayOffset) * 86_400 + hour * 3_600)
}

private func breast(_ start: Date, left: TimeInterval, right: TimeInterval, first: Side = .left) -> FeedEntry {
    let last: Side = (first == .left ? right : left) > 0 ? first.opposite : first
    return FeedEntry(id: UUID(), start: start, end: start.addingTimeInterval(left + right),
                     details: .breast(left: left, right: right, firstSide: first, lastSide: last))
}

private func bottle(_ start: Date, ml: Double, contents: BottleContents = .formula) -> FeedEntry {
    FeedEntry(id: UUID(), start: start, end: start, details: .bottle(BottleSummary(contents: contents, amountML: ml)), source: .manual)
}

@Suite("FeedEntry")
struct FeedEntryTests {
    @Test func mapsTheGuideExampleSession() {
        // 2:15 AM, left 12 min, right 9 min, ends 2:36 AM.
        let start = at(2.25)
        let switchAt = start.addingTimeInterval(12 * 60)
        let end = switchAt.addingTimeInterval(9 * 60)
        let session = SessionSnapshot(
            status: .completed,
            segments: [Segment(side: .left, start: start, end: switchAt), Segment(side: .right, start: switchAt, end: end)],
            startedAt: start, endedAt: end, notes: "sleepy"
        )
        let entry = FeedEntry(breast: session)
        #expect(entry.kind == .breast)
        #expect(entry.start == start)
        #expect(entry.end == end)
        #expect(entry.breastDuration == 21 * 60)
        #expect(entry.details == FeedEntry.Details.breast(left: 720.0, right: 540.0, firstSide: .left, lastSide: .right))
        #expect(entry.lastSide == .right)
        #expect(entry.notes == "sleepy")
        #expect(entry.bottleML == 0)
    }

    @Test func filtersByKind() {
        let b = breast(at(1), left: 600, right: 0)
        let f = bottle(at(2), ml: 90)
        #expect(FeedFilter.all.includes(b) && FeedFilter.all.includes(f))
        #expect(FeedFilter.breast.includes(b) && !FeedFilter.breast.includes(f))
        #expect(FeedFilter.bottle.includes(f) && !FeedFilter.bottle.includes(b))
    }
}

@Suite("FeedTimeline")
struct FeedTimelineTests {
    @Test func groupsByDayNewestFirstWithStartToStartGaps() {
        let yesterdayLate = breast(at(22, dayOffset: -1), left: 600, right: 600)
        let early = bottle(at(1), ml: 90)
        let morning = breast(at(3.5), left: 720, right: 540)
        let days = FeedTimeline.days(from: [early, morning, yesterdayLate], calendar: utc)

        #expect(days.map(\.day) == [midnight, midnight.addingTimeInterval(-86_400)])
        #expect(days[0].rows.map(\.entry.id) == [morning.id, early.id])
        #expect(days[0].rows[0].sincePrevious == 2.5 * 3_600)
        // The first feed of a day still shows the gap from the previous day's last feed.
        #expect(days[0].rows[1].sincePrevious == 3.0 * 3_600)
        #expect(days[1].rows.map(\.entry.id) == [yesterdayLate.id])
        #expect(days[1].rows[0].sincePrevious == nil)
    }

    @Test func gapsFollowTheFilter() {
        let a = breast(at(1), left: 600, right: 0)
        let b = bottle(at(2), ml: 60)
        let c = breast(at(4), left: 600, right: 0)
        let days = FeedTimeline.days(from: [a, b, c], filter: .breast, calendar: utc)
        #expect(days.count == 1)
        #expect(days[0].rows.map(\.entry.id) == [c.id, a.id])
        #expect(days[0].rows[0].sincePrevious == 3.0 * 3_600)
    }

    @Test func feedCrossingMidnightBelongsToTheDayItStarted() {
        let late = breast(at(23.9, dayOffset: -1), left: 900, right: 0)
        let days = FeedTimeline.days(from: [late], calendar: utc)
        #expect(days.map(\.day) == [midnight.addingTimeInterval(-86_400)])
    }

    @Test func emptyInputGivesNoDays() {
        #expect(FeedTimeline.days(from: [], calendar: utc).isEmpty)
    }
}

@Suite("DashboardSummary")
struct DashboardSummaryTests {
    @Test func emptyHistory() {
        let summary = DashboardSummary(entries: [], now: at(10), calendar: utc)
        #expect(summary.lastFeed == nil)
        #expect(summary.timeSinceLastFeed(at: at(10)) == nil)
        #expect(summary.suggestedNextSide == .left)
        #expect(summary.today == .zero)
        #expect(summary.last24Hours == .zero)
    }

    @Test func lastFeedAndTimeSinceItStarted() {
        let b = breast(at(6), left: 600, right: 600)
        let f = bottle(at(8), ml: 120)
        let summary = DashboardSummary(entries: [b, f], now: at(10.25), calendar: utc)
        #expect(summary.lastFeed?.id == f.id)
        #expect(summary.timeSinceLastFeed(at: at(10.25)) == 2.25 * 3_600)
        // A bottle doesn't change the suggestion: it comes from the last breastfeed.
        #expect(summary.lastBreastFeed?.id == b.id)
        #expect(summary.suggestedNextSide == .left) // b ended on the right
    }

    @Test func suggestsOppositeOfTheSideTheLastBreastfeedEndedOn() {
        let leftOnly = breast(at(6), left: 600, right: 0)
        #expect(DashboardSummary(entries: [leftOnly], now: at(7), calendar: utc).suggestedNextSide == .right)
    }

    @Test func todayTotalsAndAverageInterval() {
        let entries = [
            breast(at(23, dayOffset: -1), left: 600, right: 600), // yesterday, inside the last 24 h
            breast(at(1), left: 720, right: 540),
            bottle(at(4), ml: 90),
            breast(at(7), left: 600, right: 300),
            bottle(at(9), ml: 60, contents: .breastMilk),
        ]
        let summary = DashboardSummary(entries: entries, now: at(10), calendar: utc)
        #expect(summary.today.feedCount == 4)
        #expect(summary.today.breastCount == 2)
        #expect(summary.today.bottleCount == 2)
        #expect(summary.today.breastDuration == TimeInterval(720 + 540 + 600 + 300))
        #expect(summary.today.bottleML == 150)
        // Starts at 1, 4, 7, 9 → gaps 3, 3, 2 → mean 2 h 40 min.
        #expect(summary.today.averageInterval == (8.0 / 3.0) * 3_600)
        #expect(summary.last24Hours.feedCount == 5)
        #expect(summary.last24Hours.averageInterval == (10.0 / 4.0) * 3_600)
    }

    @Test func rollingWindowExcludesFeedsExactly24HoursOld() {
        let old = bottle(at(10, dayOffset: -1), ml: 60)
        let recent = bottle(at(9), ml: 60)
        let summary = DashboardSummary(entries: [old, recent], now: at(10), calendar: utc)
        #expect(summary.last24Hours.feedCount == 1)
        #expect(summary.last24Hours.averageInterval == nil)
    }

    @Test func futureEntriesAreIgnored() {
        let future = bottle(at(12), ml: 60)
        let summary = DashboardSummary(entries: [future], now: at(10), calendar: utc)
        #expect(summary.lastFeed == nil)
        #expect(summary.today.feedCount == 0)
    }
}

@Suite("Breastfeed editing")
struct BreastFeedEditTests {
    private func guideSession() -> SessionSnapshot {
        let start = at(2.25)
        let mid = start.addingTimeInterval(12 * 60)
        let end = mid.addingTimeInterval(9 * 60)
        return SessionSnapshot(
            status: .completed,
            segments: [Segment(side: .left, start: start, end: mid), Segment(side: .right, start: mid, end: end)],
            startedAt: start, endedAt: end, revision: 4, notes: "n"
        )
    }

    @Test func untouchedSimpleDraftReproducesTheSession() throws {
        let session = guideSession()
        let draft = try #require(SimpleBreastEdit(session))
        #expect(draft.firstSide == .left)
        #expect(draft.left == 12 * 60 && draft.right == 9 * 60)
        #expect(draft.apply(to: session) == session)
    }

    @Test func changingMinutesMovesTheSwitchAndTheEnd() throws {
        let session = guideSession()
        var draft = try #require(SimpleBreastEdit(session))
        draft.left = 15 * 60
        draft.right = 0
        let edited = draft.apply(to: session)
        #expect(edited.segments.count == 1)
        #expect(edited.segments[0].id == session.segments[0].id)
        #expect(edited.endedAt == session.startedAt.addingTimeInterval(15 * 60))
        #expect(SessionValidator.isValid(edited, now: at(5)))
    }

    @Test func swappingTheFirstSideReordersSegments() throws {
        var draft = try #require(SimpleBreastEdit(guideSession()))
        draft.firstSide = .right
        let edited = draft.apply(to: guideSession())
        #expect(edited.segments.map(\.side) == [.right, .left])
        #expect(edited.segments[0].end == edited.segments[1].start)
        #expect(edited.feedingDuration(at: at(5)) == 21 * 60)
    }

    @Test func sessionsWithPausesOrManySwitchesNeedSegmentsMode() {
        var paused = guideSession()
        paused.segments[1].start = paused.segments[1].start.addingTimeInterval(60)
        #expect(SimpleBreastEdit(paused) == nil)

        var many = guideSession()
        let end = many.endedAt!
        many.segments.append(Segment(side: .left, start: end, end: end.addingTimeInterval(60)))
        many.endedAt = end.addingTimeInterval(60)
        #expect(SimpleBreastEdit(many) == nil)
    }

    @Test func manualEntryEndsNowAndIsValid() {
        let now = at(10)
        let entry = SimpleBreastEdit.manualEntry(endingAt: now, firstSide: .right, left: 300, right: 600)
        let session = entry.newSession(notes: "added later")
        #expect(session.source == .manual)
        #expect(session.status == .completed)
        #expect(session.endedAt == now)
        #expect(session.segments.map(\.side) == [.right, .left])
        #expect(session.notes == "added later")
        #expect(SessionValidator.isValid(session, now: now))
    }

    @Test func normalizingSortsSegmentsAndRecomputesBounds() {
        var session = guideSession()
        session.segments.reverse()
        session.segments[0].end = session.segments[0].end!.addingTimeInterval(120) // right now ends 2 min later
        let normalized = SessionEditing.normalizedCompleted(session)
        #expect(normalized.segments.map(\.side) == [.left, .right])
        #expect(normalized.startedAt == normalized.segments[0].start)
        #expect(normalized.endedAt == guideSession().endedAt!.addingTimeInterval(120))
        #expect(SessionValidator.isValid(normalized, now: at(5)))
    }

    @Test func nextSegmentStartsWhereTheLastEndedOnTheOtherSide() {
        let session = guideSession()
        let next = SessionEditing.nextSegment(after: session, length: 120)
        #expect(next.side == .left)
        #expect(next.start == session.endedAt)
        #expect(next.end == session.endedAt!.addingTimeInterval(120))
    }
}

@MainActor
@Suite("Deleting finished feeds")
struct DeleteCompletedTests {
    @Test func deleteRemovesTheFeedRefreshesLastSideAndCanBeUndone() async throws {
        let clock = TestClock()
        let repository = InMemoryFeedingRepository()
        let reminders = RecordingReminders()
        let manager = FeedingSessionManager(repository: repository, clock: clock, reminders: reminders)

        try manager.start(side: .left)
        clock.advance(by: 600)
        try manager.end()
        clock.advance(by: 3_600)
        try manager.start(side: .right)
        clock.advance(by: 600)
        try manager.end()
        let latest = try #require(manager.lastCompletedSession)
        #expect(manager.suggestedNextSide == .left)
        await manager.waitForPendingEffects()
        let callsBefore = reminders.calls

        let deleted = try manager.deleteCompleted(sessionID: latest.id)
        #expect(deleted == latest)
        #expect(try repository.session(id: latest.id) == nil)
        #expect(manager.lastCompletedSession?.startingSide == .left)
        #expect(manager.suggestedNextSide == .right)
        await manager.waitForPendingEffects()
        #expect(reminders.calls == callsBefore + 1)

        try manager.restore(deleted)
        #expect(try repository.session(id: latest.id)?.segments == latest.segments)
        #expect(manager.lastCompletedSession?.id == latest.id)
    }

    @Test func runningFeedCantBeDeletedFromHistory() throws {
        let manager = FeedingSessionManager(repository: InMemoryFeedingRepository(), clock: TestClock())
        try manager.start(side: .left)
        let id = try #require(manager.activeSession?.id)
        #expect(throws: FeedingSessionError.statusChangeNotAllowed) { try manager.deleteCompleted(sessionID: id) }
        #expect(manager.activeSession?.id == id)
    }

    @Test func deletingAMissingFeedThrowsNotFound() {
        let manager = FeedingSessionManager(repository: InMemoryFeedingRepository(), clock: TestClock())
        let id = UUID()
        #expect(throws: FeedingSessionError.sessionNotFound(id)) { try manager.deleteCompleted(sessionID: id) }
    }
}
