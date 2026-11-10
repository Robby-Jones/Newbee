import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "NewbeeTests.\(UUID().uuidString)")!
}

/// A small Huckleberry export: two nursing feeds, two bottles, one pumping session, a sleep and a
/// diaper. All before `TestClock`'s default "now" (2027-01-15).
private let huckleberryCSV = [
    #""Type","Start","End","Duration","Start Condition","Start Location","End Condition","Notes""#,
    #""Sleep","2026-09-01 19:32","2026-09-02 06:57","11:25",,,,"#,
    #""Feed","2026-09-01 17:00","2026-09-01 17:14","00:14","00:07R","Breast","00:06L","#,
    #""Feed","2026-09-01 20:00","2026-09-01 20:29","00:29","00:29R","Breast",,"#,
    #""Feed","2026-09-01 11:00",,,"Breast Milk","Bottle","4.0oz","#,
    #""Feed","2026-09-01 08:00",,,"Formula","Bottle","120ml","first one""#,
    #""Diaper","2026-09-01 09:00",,,,,"Pee","#,
    #""Pump","2026-09-01 03:00",,"00:20","100ml",,"120ml","#,
].joined(separator: "\r\n") + "\r\n"

private func writeFile(_ text: String, name: String = "huckleberry.csv") throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try Data(text.utf8).write(to: url)
    return url
}

@MainActor
@Suite("Huckleberry import")
struct FeedImportTests {
    let clock = TestClock()

    func makeDependencies() -> AppDependencies {
        AppDependencies(clock: clock, storage: .inMemory, notifications: FakeNotificationClient(), defaults: freshDefaults())
    }

    @Test func previewSavesNothingAndCommitAddsEverySupportedRow() async throws {
        let dependencies = makeDependencies()
        let context = try #require(dependencies.modelContainer?.mainContext)
        let plan = try dependencies.prepareHuckleberryImport(from: try writeFile(huckleberryCSV))
        #expect(plan.breastCount == 2)
        #expect(plan.bottleCount == 2)
        #expect(plan.pumpCount == 1)
        #expect(plan.unsupportedByType == ["Sleep": 1, "Diaper": 1])
        #expect(try context.fetchCount(FetchDescriptor<FeedingSession>()) == 0)

        let added = try await dependencies.commitImport(plan)
        #expect(added == 5)
        #expect(dependencies.importedEntryCount() == 5)

        let feeds = try context.fetch(FeedingSession.completedFeeds()).compactMap(\.feedEntry)
        #expect(feeds.count == 4)
        #expect(feeds.allSatisfy { $0.source == .imported })
        let pumps = try context.fetch(FeedingSession.completedPumps()).compactMap(\.pumpEntry)
        #expect(pumps.map(\.totalML) == [220])

        let formula = try #require(feeds.first { if case .bottle(let b) = $0.details { b.contents == .formula } else { false } })
        #expect(formula.notes == "first one")
        #expect(formula.bottleML == 120)

        // The newest imported breastfeed becomes "last feed" for the timer and Live Activity.
        let last = try #require(dependencies.sessionManager.lastCompletedSession)
        #expect(last.source == .imported)
        #expect(last.segments.map(\.side) == [.right])
    }

    @Test func importingTheSameFileAgainAddsNothing() async throws {
        let dependencies = makeDependencies()
        let url = try writeFile(huckleberryCSV)
        try await dependencies.commitImport(try dependencies.prepareHuckleberryImport(from: url))

        let again = try dependencies.prepareHuckleberryImport(from: url)
        #expect(again.isEmpty)
        #expect(again.duplicates == 5)
        #expect(try await dependencies.commitImport(again) == 0)
        #expect(dependencies.importedEntryCount() == 5)
    }

    @Test func feedsAlreadyLoggedInNewbeeAreSkipped() async throws {
        let dependencies = makeDependencies()
        let start = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 8)))
        _ = try dependencies.bottleLog.save(BottleDraft(contents: .formula, amount: BottleAmount(120, .milliliters), startedAt: start.addingTimeInterval(25)))

        let plan = try dependencies.prepareHuckleberryImport(from: try writeFile(huckleberryCSV))
        #expect(plan.duplicates == 1)
        #expect(plan.bottleCount == 1)
    }

    @Test func removingImportedDataKeepsWhatWasLoggedInNewbee() async throws {
        let dependencies = makeDependencies()
        let context = try #require(dependencies.modelContainer?.mainContext)
        let manager = dependencies.sessionManager
        try manager.start(side: .left)
        clock.advance(by: 10 * 60)
        _ = try manager.end()
        try await dependencies.commitImport(try dependencies.prepareHuckleberryImport(from: try writeFile(huckleberryCSV)))
        #expect(try context.fetchCount(FetchDescriptor<FeedingSession>()) == 6)

        let removed = try await dependencies.removeImportedData()
        #expect(removed == 5)
        #expect(dependencies.importedEntryCount() == 0)
        let left = try context.fetch(FetchDescriptor<FeedingSession>())
        #expect(left.count == 1)
        #expect(left.first?.source == .timer)
        // Children go with their sessions.
        #expect(try context.fetchCount(FetchDescriptor<FeedingSegment>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<BottleDetails>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PumpDetails>()) == 0)
        #expect(manager.lastCompletedSession?.source == .timer)
    }

    @Test func importedEntriesAttachToTheBabyProfile() async throws {
        let dependencies = makeDependencies()
        let context = try #require(dependencies.modelContainer?.mainContext)
        let baby = Baby(name: "Juniper")
        context.insert(baby)
        try context.save()
        try await dependencies.commitImport(try dependencies.prepareHuckleberryImport(from: try writeFile(huckleberryCSV)))
        #expect(try context.fetch(FetchDescriptor<FeedingSession>()).allSatisfy { $0.baby?.id == baby.id })
    }

    @Test func editingAnImportedBottleKeepsItTaggedImported() async throws {
        let dependencies = makeDependencies()
        try await dependencies.commitImport(try dependencies.prepareHuckleberryImport(from: try writeFile(huckleberryCSV)))
        let context = try #require(dependencies.modelContainer?.mainContext)
        let bottle = try #require(try context.fetch(FeedingSession.completedFeeds()).first { $0.kind == .bottle }?.bottleEntry)
        var draft = BottleDraft(editing: bottle)
        draft.notes = "edited"
        _ = try dependencies.bottleLog.save(draft)
        #expect(dependencies.importedEntryCount() == 5)
    }

    @Test func otherFilesAreRejectedWithAHelpfulError() throws {
        let dependencies = makeDependencies()
        let newbeeExport = try writeFile(FeedCSV.header.joined(separator: ",") + "\r\n")
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).csv")
        for url in [newbeeExport, missing] {
            do {
                _ = try dependencies.prepareHuckleberryImport(from: url)
                Issue.record("\(url.lastPathComponent) should be rejected")
            } catch let error as AppDependencies.ImportError {
                #expect(error.errorDescription?.isEmpty == false)
            }
        }
    }
}
