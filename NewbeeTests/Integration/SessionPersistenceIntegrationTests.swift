import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// The session engine running against real SwiftData stores (docs/TESTING.md §3).
@MainActor
@Suite("Session persistence integration")
struct SessionPersistenceIntegrationTests {
    let engine = SessionEngine()

    func makeRepository() throws -> (ModelContainer, SwiftDataFeedingRepository) {
        let container = try makeInMemoryContainer()
        return (container, SwiftDataFeedingRepository(context: container.mainContext))
    }

    func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "NewbeeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Newbee.store")
    }

    // MARK: Repository

    @Test func snapshotRoundTripsExactly() throws {
        let (_, repository) = try makeRepository()
        let clock = TestClock()
        var s = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 720)
        s = try engine.apply(.switchTo(.right), to: s, at: clock.instant()).snapshot
        s.notes = "sleepy"

        try repository.save(s, modifiedAt: clock.now)
        #expect(try repository.session(id: s.id) == s)
        #expect(try repository.activeSession() == s)
    }

    @Test func savingReplacesSegmentsAndDeletesRemovedOnes() throws {
        let (container, repository) = try makeRepository()
        let clock = TestClock()
        var s = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 300)
        s = try engine.apply(.switchTo(.right), to: s, at: clock.instant()).snapshot
        try repository.save(s, modifiedAt: clock.now)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSegment>()) == 2)

        // A switch straight back merges the blip away: one segment must disappear from the store.
        clock.advance(by: 0.3)
        s = try engine.apply(.switchTo(.left), to: s, at: clock.instant()).snapshot
        try repository.save(s, modifiedAt: clock.now)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSegment>()) == 1)
        #expect(try repository.session(id: s.id) == s)
    }

    @Test func openSessionsAreBreastfeedsThatAreActiveOrPausedNewestFirst() throws {
        let (container, repository) = try makeRepository()
        let clock = TestClock()
        let older = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 600)
        let newer = try engine.apply(.start(.right), to: nil, at: clock.instant()).snapshot
        var done = try engine.apply(.start(.left), to: nil, at: clock.instant()).snapshot
        clock.advance(by: 60)
        done = try engine.apply(.end, to: done, at: clock.instant()).snapshot
        try repository.save([older, newer, done], modifiedAt: clock.now)
        container.mainContext.insert(FeedingSession(kind: .bottle, status: .active, startedAt: clock.now))
        try container.mainContext.save()

        #expect(try repository.openSessions().map(\.id) == [newer.id, older.id])
        #expect(try repository.recentCompletedSessions(limit: 5).map(\.id) == [done.id])
    }

    @Test func newSessionsAttachToTheBabyProfile() throws {
        let (container, repository) = try makeRepository()
        let baby = Baby(name: "Ada")
        container.mainContext.insert(baby)
        try container.mainContext.save()
        let s = try engine.apply(.start(.left), to: nil, at: TestClock().instant()).snapshot
        try repository.save(s, modifiedAt: .now)
        let stored = try container.mainContext.fetch(FetchDescriptor<FeedingSession>())
        #expect(stored.first?.baby?.name == "Ada")
    }

    @Test func deleteRemovesSessionAndSegments() throws {
        let (container, repository) = try makeRepository()
        let s = try engine.apply(.start(.left), to: nil, at: TestClock().instant()).snapshot
        try repository.save(s, modifiedAt: .now)
        try repository.delete(sessionID: s.id)
        try repository.delete(sessionID: s.id)   // deleting twice is fine
        #expect(try repository.session(id: s.id) == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSegment>()) == 0)
    }

    // MARK: Manager on SwiftData

    @Test func managerRunsTheSpecExampleAgainstSwiftData() throws {
        let (_, repository) = try makeRepository()
        let clock = TestClock()
        let manager = FeedingSessionManager(repository: repository, clock: clock)
        try manager.start(side: .left)
        clock.advance(by: 12 * 60)
        try manager.switchSide(to: .right)
        clock.advance(by: 9 * 60)
        try manager.end()

        let done = try #require(try repository.recentCompletedSessions(limit: 1).first)
        #expect(abs(done.duration(on: .left, at: clock.now) - 12 * 60) < 0.001)
        #expect(abs(done.duration(on: .right, at: clock.now) - 9 * 60) < 0.001)
        #expect(done.segments.count == 2)
        #expect(try repository.openSessions().isEmpty)
    }

    @Test func activeSessionSurvivesTerminationAndRelaunch() async throws {
        let url = try temporaryStoreURL()
        let clock = TestClock()
        let beforeTermination: SessionSnapshot?
        do {
            let container = try PersistenceController.makeContainer(.file(url))
            let manager = FeedingSessionManager(
                repository: SwiftDataFeedingRepository(context: container.mainContext),
                clock: clock
            )
            try manager.start(side: .left)
            clock.advance(by: 300)
            try manager.switchSide(to: .right)
            beforeTermination = manager.activeSession
        }

        // The process dies; 20 minutes later the app launches on the same store.
        clock.advance(by: 20 * 60)
        let container = try PersistenceController.makeContainer(.file(url))
        let manager = FeedingSessionManager(
            repository: SwiftDataFeedingRepository(context: container.mainContext),
            clock: clock
        )
        let recovery = RecoveryCoordinator(manager: manager)
        await recovery.reconcile()

        #expect(manager.activeSession == beforeTermination)
        #expect(manager.activeSession?.openSegment?.side == .right)
        #expect(abs((manager.activeSession?.feedingDuration(at: clock.now) ?? 0) - 25 * 60) < 0.001)
        #expect(manager.recoveryPrompt == nil)
    }

    @Test func appDependenciesWireAWorkingManager() throws {
        let dependencies = AppDependencies(clock: TestClock(), storage: .inMemory)
        try dependencies.sessionManager.start(side: .right)
        #expect(dependencies.sessionManager.activeSession?.openSegment?.side == .right)
        #expect(dependencies.storeError == nil)
    }
}
