import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

/// Guards for the on-disk store. Once v1 is on the App Store, a store that won't open after an
/// update locks parents out of their history, so:
/// - every older schema must still migrate, including a feed that was running when the app
///   was updated, and
/// - the shipped schema must never change silently. Editing a `NewbeeSchemaV2` model without
///   adding `NewbeeSchemaV3` and a migration stage makes SwiftData refuse the existing store.
@MainActor
@Suite("Schema migration")
struct SchemaMigrationTests {
    /// 2026-11-07 06:00 UTC.
    let now = Date(timeIntervalSince1970: 1_793_944_800)

    func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "NewbeeMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Newbee.store")
    }

    /// Writes a V1 store holding a finished breastfeed with notes and a feed that is still
    /// running (left for 5 minutes, then right since 5 minutes ago), as the last V1 build would.
    func writeVersionOneStore(at url: URL) throws -> (running: SessionSnapshot, finished: SessionSnapshot) {
        let finished = SessionSnapshot(
            status: .completed,
            segments: [
                Segment(side: .right, start: now.addingTimeInterval(-3 * 3_600), end: now.addingTimeInterval(-3 * 3_600 + 720),
                        startMonotonic: 100, startBootID: "boot-1"),
                Segment(side: .left, start: now.addingTimeInterval(-3 * 3_600 + 720), end: now.addingTimeInterval(-3 * 3_600 + 1_260),
                        startMonotonic: 820, startBootID: "boot-1"),
            ],
            startedAt: now.addingTimeInterval(-3 * 3_600),
            endedAt: now.addingTimeInterval(-3 * 3_600 + 1_260),
            revision: 4,
            timeZoneID: "America/New_York",
            source: .timer,
            notes: "Sleepy, good latch"
        )
        let running = SessionSnapshot(
            status: .active,
            segments: [
                Segment(side: .left, start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300),
                        startMonotonic: 400, startBootID: "boot-1"),
                Segment(side: .right, start: now.addingTimeInterval(-300), startMonotonic: 700, startBootID: "boot-1"),
            ],
            startedAt: now.addingTimeInterval(-600),
            revision: 2,
            timeZoneID: "America/New_York",
            source: .timer,
            needsReview: false,
            recoveryAcknowledgedAt: now.addingTimeInterval(-60)
        )

        let schema = Schema(versionedSchema: NewbeeSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        let baby = NewbeeSchemaV1.Baby(name: "Millie", birthDate: now.addingTimeInterval(-20 * 86_400))
        context.insert(baby)
        for snapshot in [finished, running] {
            let session = NewbeeSchemaV1.FeedingSession(
                id: snapshot.id, kind: .breast, status: snapshot.status, startedAt: snapshot.startedAt,
                timeZoneID: snapshot.timeZoneID, source: snapshot.source
            )
            session.endedAt = snapshot.endedAt
            session.revision = snapshot.revision
            session.notes = snapshot.notes
            session.needsReview = snapshot.needsReview
            session.recoveryAcknowledgedAt = snapshot.recoveryAcknowledgedAt
            context.insert(session)
            session.baby = baby
            for value in snapshot.segments {
                let segment = NewbeeSchemaV1.FeedingSegment(
                    id: value.id, side: value.side, startedAt: value.start, endedAt: value.end,
                    startMonotonic: value.startMonotonic, startBootID: value.startBootID
                )
                context.insert(segment)
                segment.session = session
            }
        }
        try context.save()
        return (running, finished)
    }

    @Test func breastfeedsMigrateExactly() throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (running, finished) = try writeVersionOneStore(at: url)

        let container = try PersistenceController.makeContainer(.file(url))
        let repository = SwiftDataFeedingRepository(container: container)
        #expect(try repository.activeSession() == running)
        #expect(try repository.session(id: finished.id) == finished)
        #expect(try repository.recentCompletedSessions(limit: 5) == [finished])
        let babies = try container.mainContext.fetch(FetchDescriptor<Baby>())
        #expect(babies.map(\.name) == ["Millie"])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FeedingSegment>()) == 4)
        #expect(try container.mainContext.fetch(FetchDescriptor<FeedingSession>()).allSatisfy { $0.pump == nil && $0.baby?.name == "Millie" })
    }

    @Test func aFeedRunningDuringTheUpdateKeepsTicking() async throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (running, _) = try writeVersionOneStore(at: url)

        // The updated app launches on the same boot: wall and continuous clocks agree.
        let clock = TestClock(wall: now, monotonic: 1_000)
        let container = try PersistenceController.makeContainer(.file(url))
        let manager = FeedingSessionManager(repository: SwiftDataFeedingRepository(container: container), clock: clock)
        await RecoveryCoordinator(manager: manager).reconcile()
        #expect(manager.activeSession == running)
        #expect(manager.recoveryPrompt == nil)
        #expect(abs((manager.activeSession?.feedingDuration(at: clock.now) ?? 0) - 10 * 60) < 0.001)

        clock.advance(by: 4 * 60)
        try manager.switchSide(to: .left)
        clock.advance(by: 3 * 60)
        try manager.end()
        let done = try #require(manager.lastCompletedSession)
        #expect(done.id == running.id)
        #expect(SessionValidator.isValid(done, now: clock.now))
        #expect(abs(done.duration(on: .left, at: clock.now) - 8 * 60) < 0.001)
        #expect(abs(done.duration(on: .right, at: clock.now) - 9 * 60) < 0.001)
    }

    @Test func theAppOpensTheNewestSchemaInThePlan() {
        let schemas = NewbeeMigrationPlan.schemas
        #expect(ObjectIdentifier(schemas.last!) == ObjectIdentifier(NewbeeSchemaV2.self))
        #expect(NewbeeMigrationPlan.stages.count == schemas.count - 1)
        // Each version is new, so SwiftData can tell the stored version from the current one.
        let versions = schemas.map { "\($0.versionIdentifier)" }
        #expect(Set(versions).count == versions.count)
    }

    /// The shape of the shipped schema. If this fails, don't update the list: copy V2 to a new
    /// `NewbeeSchemaV3`, make the change there, point the aliases and `PersistenceController`
    /// at V3, and add a V2 → V3 stage to `NewbeeMigrationPlan` (docs/DATA_MODEL.md).
    @Test func versionTwoIsFrozen() {
        let schema = Schema(versionedSchema: NewbeeSchemaV2.self)
        var shape: [String] = []
        for entity in schema.entities {
            for (name, attribute) in entity.attributesByName {
                shape.append("\(entity.name).\(name)\(attribute.isOptional ? "?" : "")")
            }
            for (name, relationship) in entity.relationshipsByName {
                shape.append("\(entity.name).\(name) -> \(relationship.destination)")
            }
        }
        #expect(shape.sorted() == [
            "Baby.birthDate?",
            "Baby.createdAt",
            "Baby.id",
            "Baby.name",
            "Baby.sessions -> FeedingSession",
            "BottleDetails.amountML",
            "BottleDetails.contentsRaw",
            "BottleDetails.durationSeconds?",
            "BottleDetails.enteredUnitRaw",
            "BottleDetails.session -> FeedingSession",
            "FeedingSegment.endedAt?",
            "FeedingSegment.id",
            "FeedingSegment.session -> FeedingSession",
            "FeedingSegment.sideRaw",
            "FeedingSegment.startBootID?",
            "FeedingSegment.startMonotonic?",
            "FeedingSegment.startedAt",
            "FeedingSession.baby -> Baby",
            "FeedingSession.bottle -> BottleDetails",
            "FeedingSession.createdAt",
            "FeedingSession.endedAt?",
            "FeedingSession.id",
            "FeedingSession.kindRaw",
            "FeedingSession.modifiedAt",
            "FeedingSession.needsReview",
            "FeedingSession.notes",
            "FeedingSession.pump -> PumpDetails",
            "FeedingSession.recoveryAcknowledgedAt?",
            "FeedingSession.revision",
            "FeedingSession.segments -> FeedingSegment",
            "FeedingSession.sourceRaw",
            "FeedingSession.startedAt",
            "FeedingSession.statusRaw",
            "FeedingSession.timeZoneID",
            "PumpDetails.durationSeconds?",
            "PumpDetails.enteredUnitRaw",
            "PumpDetails.leftML",
            "PumpDetails.rightML",
            "PumpDetails.session -> FeedingSession",
        ])
    }
}
