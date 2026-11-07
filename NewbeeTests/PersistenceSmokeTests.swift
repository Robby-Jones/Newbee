import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

@MainActor
@Suite("Persistence smoke tests")
struct PersistenceSmokeTests {
    @Test func savesAndFetchesASessionWithSegments() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let baby = Baby(name: "Test")
        let session = FeedingSession(kind: .breast, status: .completed, startedAt: start)
        session.baby = baby
        session.endedAt = start.addingTimeInterval(21 * 60)
        let left = FeedingSegment(side: .left, startedAt: start, endedAt: start.addingTimeInterval(12 * 60))
        let right = FeedingSegment(side: .right, startedAt: start.addingTimeInterval(12 * 60), endedAt: start.addingTimeInterval(21 * 60))
        context.insert(baby)
        context.insert(session)
        session.segments = [right, left]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<FeedingSession>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.orderedSegments.map(\.side) == [.left, .right])
        #expect(fetched.first?.baby?.name == "Test")
    }

    @Test func deletingASessionCascadesToSegmentsAndBottle() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let session = FeedingSession(kind: .bottle, status: .completed, startedAt: .now)
        context.insert(session)
        session.bottle = BottleDetails(contents: .formula, amountML: 90, enteredUnit: .milliliters)
        session.segments = [FeedingSegment(side: .left, startedAt: .now)]
        try context.save()

        context.delete(session)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<FeedingSegment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BottleDetails>()) == 0)
    }

    @Test func predicatesOnRawStatusWork() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        context.insert(FeedingSession(kind: .breast, status: .active, startedAt: .now))
        context.insert(FeedingSession(kind: .breast, status: .completed, startedAt: .now))
        try context.save()

        let active = SessionStatus.active.rawValue
        let descriptor = FetchDescriptor<FeedingSession>(predicate: #Predicate { $0.statusRaw == active })
        #expect(try context.fetchCount(descriptor) == 1)
    }
}
