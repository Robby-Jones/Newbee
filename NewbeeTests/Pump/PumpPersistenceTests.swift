import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// Pumping sessions against a real SwiftData store, and the V1 → V2 migration that added them.
@MainActor
@Suite("Pump persistence")
struct PumpPersistenceTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func makeRepository() throws -> (ModelContainer, SwiftDataPumpRepository) {
        let container = try makeInMemoryContainer()
        return (container, SwiftDataPumpRepository(container: container))
    }

    @Test func entryRoundTripsExactly() throws {
        let (container, repository) = try makeRepository()
        let entry = PumpEntry(
            startedAt: start,
            leftML: BottleAmount(3, .fluidOunces).milliliters,
            rightML: 0,
            enteredUnit: .fluidOunces,
            durationSeconds: 900,
            notes: "froze it",
            timeZoneID: "Europe/London"
        )
        try repository.save(entry, modifiedAt: start)
        #expect(try repository.pump(id: entry.id) == entry)

        let session = try #require(try container.mainContext.fetch(FetchDescriptor<FeedingSession>()).first)
        #expect(session.kind == .pump)
        #expect(session.status == .completed)
        #expect(session.source == .manual)
        #expect(session.endedAt == start.addingTimeInterval(900))
        #expect(session.bottle == nil)
        #expect((session.segments ?? []).isEmpty)
    }

    @Test func savingAgainEditsInPlaceAndDeleteRemovesDetails() throws {
        let (container, repository) = try makeRepository()
        var entry = PumpEntry(startedAt: start, leftML: 60, rightML: 60)
        try repository.save(entry, modifiedAt: start)
        entry.rightML = 90
        try repository.save(entry, modifiedAt: start.addingTimeInterval(60))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PumpDetails>()) == 1)
        #expect(try repository.pump(id: entry.id) == entry)

        try repository.deletePump(id: entry.id)
        try repository.deletePump(id: entry.id)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSession>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PumpDetails>()) == 0)
    }

    /// Pumping isn't a feed: History, Home, Insights and reminders never see it as one.
    @Test func feedQueriesLeavePumpingOut() throws {
        let (container, repository) = try makeRepository()
        let bottles = SwiftDataBottleRepository(container: container)
        try bottles.save(BottleEntry(startedAt: start, contents: .formula, amountML: 90), modifiedAt: start)
        let pump = PumpEntry(startedAt: start.addingTimeInterval(600), leftML: 60, rightML: 60)
        try repository.save(pump, modifiedAt: start)

        let context = container.mainContext
        #expect(try context.fetch(FeedingSession.completedFeeds()).map(\.kind) == [.bottle])
        #expect(try context.fetch(FeedingSession.completedFeeds(limit: 1)).map(\.kind) == [.bottle])
        #expect(try context.fetch(FeedingSession.completedFeeds(from: start, to: start.addingTimeInterval(3600))).map(\.kind) == [.bottle])
        #expect(try context.fetch(FeedingSession.completedPumps()).compactMap(\.pumpEntry) == [pump])
        #expect(try context.fetch(FeedingSession.completedPumps(from: start, to: start.addingTimeInterval(60))).isEmpty)
        #expect(try bottles.recentBottles(limit: 5).count == 1)
        #expect(try repository.recentPumps(limit: 5) == [pump])
    }

    @Test func logWiredThroughAppDependencies() throws {
        let dependencies = AppDependencies(clock: TestClock(), storage: .inMemory)
        let result = try dependencies.pumpLog.save(dependencies.pumpLog.newDraft(unit: .milliliters))
        #expect(try dependencies.pumpLog.recent(limit: 1) == [result.saved])
    }

    /// A store written by a build before pumping (schema V1) opens with today's schema, keeps
    /// its feeds, and accepts pumping sessions.
    @Test func versionOneStoreMigrates() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewbeeMigration-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Newbee.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let bottleID = UUID()
        do {
            let schema = Schema(versionedSchema: NewbeeSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext
            let baby = NewbeeSchemaV1.Baby(name: "Millie")
            context.insert(baby)
            let session = NewbeeSchemaV1.FeedingSession(id: bottleID, kind: .bottle, status: .completed, startedAt: start, source: .manual)
            session.endedAt = start
            context.insert(session)
            session.baby = baby
            let details = NewbeeSchemaV1.BottleDetails(contents: .formula, amountML: 90, enteredUnit: .milliliters)
            context.insert(details)
            session.bottle = details
            try context.save()
        }

        let container = try PersistenceController.makeContainer(.file(url))
        let bottles = SwiftDataBottleRepository(container: container)
        #expect(try bottles.bottle(id: bottleID)?.amountML == 90)
        #expect(try container.mainContext.fetch(FetchDescriptor<Baby>()).map(\.name) == ["Millie"])

        let pumps = SwiftDataPumpRepository(container: container)
        let pump = PumpEntry(startedAt: start.addingTimeInterval(3600), leftML: 50, rightML: 40)
        try pumps.save(pump, modifiedAt: start)
        #expect(try pumps.pump(id: pump.id) == pump)
        #expect(try container.mainContext.fetch(FeedingSession.completedPumps()).first?.baby?.name == "Millie")
    }
}
