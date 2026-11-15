import Foundation
import Testing
@testable import NewbeeKit

// MARK: - Fakes

/// A dictionary-backed store of feeds and babies.
@MainActor
final class InMemorySyncStore: SyncLocalStore {
    var feeds: [UUID: FeedPayload] = [:]
    var babies: [UUID: BabyPayload] = [:]
    var photos: [UUID: Data] = [:]
    var shift: NightShift?
    var applyCount = 0
    var failure: (any Error)?
    /// Simulates a store that can't hold every detail: notes are cut to this length when applied.
    var notesLimit: Int?

    func items() throws -> [SyncKey: SyncLocalItem] {
        var items: [SyncKey: SyncLocalItem] = [:]
        for feed in feeds.values {
            items[feed.key] = SyncLocalItem(fingerprint: feed.fingerprint(), changedAt: feed.modifiedAt)
        }
        for baby in babies.values {
            items[baby.key] = SyncLocalItem(fingerprint: baby.fingerprint(attachment: photos[baby.id]), changedAt: baby.createdAt)
        }
        if let shift {
            items[shift.key] = SyncLocalItem(fingerprint: shift.fingerprint(), changedAt: shift.changedAt)
        }
        return items
    }

    func content(for key: SyncKey) throws -> SyncContent? {
        if key.kind == .nightShift { return shift?.content() }
        guard let id = UUID(uuidString: key.id) else { return nil }
        switch key.kind {
        case .feed: return feeds[id]?.content()
        case .baby: return babies[id]?.content(attachment: photos[id])
        case .nightShift: return nil
        }
    }

    func apply(_ contents: [SyncKey: SyncContent]) throws -> [SyncKey: Int64] {
        if let failure { throw failure }
        applyCount += 1
        var stored: [SyncKey: Int64] = [:]
        for (key, content) in contents {
            switch key.kind {
            case .feed:
                guard var feed = FeedPayload.decode(content) else { continue }
                if let notesLimit { feed.notes = String(feed.notes.prefix(notesLimit)) }
                feeds[feed.id] = feed
                stored[key] = feed.fingerprint()
            case .baby:
                guard let baby = BabyPayload.decode(content) else { continue }
                babies[baby.id] = baby
                photos[baby.id] = content.attachment
                stored[key] = baby.fingerprint(attachment: content.attachment)
            case .nightShift:
                guard let incoming = NightShift.decode(content) else { continue }
                shift = incoming
                stored[key] = incoming.fingerprint()
            }
        }
        return stored
    }

    func delete(_ keys: [SyncKey]) throws {
        if let failure { throw failure }
        for key in keys {
            if key.kind == .nightShift { shift = nil }
            guard let id = UUID(uuidString: key.id) else { continue }
            feeds[id] = nil
            babies[id] = nil
            photos[id] = nil
        }
    }
}

/// One zone on a pretend server, with CloudKit's rules: a save over an existing record must carry
/// that record's current tag, or it comes back as a conflict with the server's version.
@MainActor
final class FakeCloudZone {
    enum SaveResult {
        case saved(SyncRecord)
        case conflict(server: SyncRecord)
        case unknownItem
    }

    private(set) var records: [SyncKey: SyncRecord] = [:]
    private var log: [(sequence: Int, key: SyncKey)] = []
    private var sequence = 0
    private(set) var saveCount = 0

    private func tag() -> Data {
        sequence += 1
        return Data("tag-\(sequence)".utf8)
    }

    func save(_ record: SyncRecord) -> SaveResult {
        if let existing = records[record.key] {
            guard record.systemFields == existing.systemFields else { return .conflict(server: existing) }
        } else if record.systemFields != nil {
            return .unknownItem
        }
        var saved = record
        saved.systemFields = tag()
        records[record.key] = saved
        log.append((sequence, record.key))
        saveCount += 1
        return .saved(saved)
    }

    func delete(_ key: SyncKey) {
        guard records[key] != nil else { return }
        records[key] = nil
        sequence += 1
        log.append((sequence, key))
    }

    /// Everything that changed after `cursor`, a device's own changes included, as CloudKit does.
    func changes(since cursor: Int) -> (modifications: [SyncRecord], deletions: [SyncKey], cursor: Int) {
        var keys: [SyncKey] = []
        for entry in log where entry.sequence > cursor && !keys.contains(entry.key) {
            keys.append(entry.key)
        }
        return (keys.compactMap { records[$0] }, keys.filter { records[$0] == nil }, sequence)
    }
}

/// A phone: its store, its sync core and its place in the server's change feed.
@MainActor
final class FakeDevice {
    let store = InMemorySyncStore()
    let clock: TestClock
    private(set) var core: SyncCore
    private var zone: FakeCloudZone
    private var cursor = 0

    init(zone: FakeCloudZone, clock: TestClock) {
        self.zone = zone
        self.clock = clock
        core = SyncCore(store: store, clock: clock)
    }

    /// Starts over against another zone, as when a parent joins a shared log.
    func move(to zone: FakeCloudZone) {
        self.zone = zone
        cursor = 0
        core.forgetServer()
    }

    /// Relaunches the app: the ledger comes back from disk.
    func relaunch() throws {
        let data = try JSONEncoder().encode(core.ledger)
        core = SyncCore(store: store, ledger: try JSONDecoder().decode(SyncLedger.self, from: data), clock: clock)
    }

    /// One fetch and one send, the way `CloudSyncEngine` drives the core. Returns true if anything moved.
    @discardableResult
    func sync() throws -> Bool {
        var moved = try fetch()
        let pending = try core.scan()
        for key in pending.saves.sorted(by: { $0.id < $1.id }) {
            guard let record = try core.outgoingRecord(for: key) else { continue }
            moved = true
            switch zone.save(record) {
            case .saved(let saved): core.didSave(saved)
            case .conflict(let server): try core.receive(modifications: [server])
            case .unknownItem: core.serverLost(key)
            }
        }
        for key in pending.deletes where core.needsDelete(key) {
            moved = true
            zone.delete(key)
            core.didDelete(key)
        }
        return moved
    }

    @discardableResult
    func fetch() throws -> Bool {
        let changes = zone.changes(since: cursor)
        cursor = changes.cursor
        return try core.receive(modifications: changes.modifications, deletions: changes.deletions)
    }
}

@MainActor
func syncUntilQuiet(_ devices: FakeDevice..., sourceLocation: SourceLocation = #_sourceLocation) throws {
    for _ in 0..<10 {
        var moved = false
        for device in devices where try device.sync() {
            moved = true
        }
        if !moved { return }
    }
    Issue.record("Sync never settled", sourceLocation: sourceLocation)
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func bottle(_ id: UUID = UUID(), at date: Date = start, amount: Double = 90, notes: String = "") -> FeedPayload {
    FeedPayload(
        id: id, kind: "bottle", status: "completed", startedAt: date, endedAt: date, timeZoneID: "America/Chicago",
        notes: notes, source: "manual", needsReview: false, recoveryAcknowledgedAt: nil, revision: 0,
        createdAt: date, modifiedAt: date, segments: [],
        bottle: .init(contents: "formula", amountML: amount, enteredUnit: "mL", durationSeconds: nil), pump: nil
    )
}

// MARK: - Fingerprints

@Suite("Sync fingerprints")
struct FingerprintTests {
    /// The fingerprint is saved on every device. If this value ever changes, every item would
    /// look edited after an update, so the algorithm must stay as it is.
    @Test func theAlgorithmIsPinned() {
        let feed = FeedPayload(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, kind: "breast", status: "completed",
            startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), endedAt: Date(timeIntervalSinceReferenceDate: 800_000_900.5),
            timeZoneID: "America/Chicago", notes: "Sleepy 😴", source: "timer", needsReview: false,
            recoveryAcknowledgedAt: nil, revision: 4,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), modifiedAt: Date(timeIntervalSinceReferenceDate: 800_000_901),
            segments: [
                .init(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!, side: "left",
                      startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), endedAt: Date(timeIntervalSinceReferenceDate: 800_000_900.5),
                      startMonotonic: 1234.5, startBootID: "boot"),
            ],
            bottle: nil, pump: nil
        )
        #expect(feed.fingerprint() == PinnedFingerprints.feed)
        let baby = BabyPayload(
            id: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!, name: "Ella", birthDate: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 790_000_000)
        )
        #expect(baby.fingerprint(attachment: Data([1, 2, 3])) == PinnedFingerprints.baby)
    }

    @Test func anyChangeChangesTheFingerprint() {
        let feed = bottle()
        var edited = feed
        edited.notes = "Spit up a little"
        #expect(feed.fingerprint() != edited.fingerprint())
        edited = feed
        edited.bottle?.amountML = 91
        #expect(feed.fingerprint() != edited.fingerprint())
        edited = feed
        edited.endedAt = nil
        #expect(feed.fingerprint() != edited.fingerprint())

        let baby = BabyPayload(id: UUID(), name: "Ella", birthDate: nil, createdAt: start)
        #expect(baby.fingerprint() != baby.fingerprint(attachment: Data([1])))
        #expect(baby.fingerprint(attachment: Data([1])) != baby.fingerprint(attachment: Data([2])))
    }

    /// Travelling as JSON and back must not look like an edit.
    @Test func theFingerprintSurvivesTheTrip() throws {
        let feed = FeedPayload(
            id: UUID(), kind: "breast", status: "active", startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.123456),
            endedAt: nil, timeZoneID: "Europe/Paris", notes: "", source: "timer", needsReview: true,
            recoveryAcknowledgedAt: Date(timeIntervalSinceReferenceDate: 800_000_111.987654321), revision: 2,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000.1), modifiedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.2),
            segments: [.init(id: UUID(), side: "right", startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.123456), endedAt: nil, startMonotonic: 0.1 + 0.2, startBootID: nil)],
            bottle: nil, pump: .init(leftML: 59.147059125, rightML: 1.0 / 3.0, enteredUnit: "oz", durationSeconds: 600)
        )
        let content = feed.content()
        let decoded = try #require(FeedPayload.decode(content))
        #expect(decoded == feed)
        #expect(SyncCodec.fingerprint(of: content, kind: .feed) == feed.fingerprint())
    }

    @Test func segmentsAreKeptInOneOrder() {
        let first = FeedPayload.Segment(id: UUID(), side: "left", startedAt: start, endedAt: start.addingTimeInterval(60), startMonotonic: nil, startBootID: nil)
        let second = FeedPayload.Segment(id: UUID(), side: "right", startedAt: start.addingTimeInterval(90), endedAt: nil, startMonotonic: nil, startBootID: nil)
        var a = bottle()
        a = FeedPayload(id: a.id, kind: "breast", status: "active", startedAt: start, endedAt: nil, timeZoneID: a.timeZoneID, notes: "", source: "timer", needsReview: false, recoveryAcknowledgedAt: nil, revision: 0, createdAt: start, modifiedAt: start, segments: [second, first], bottle: nil, pump: nil)
        #expect(a.segments == [first, second])
    }

    @Test func unreadableContentHasNoFingerprint() {
        #expect(SyncCodec.fingerprint(of: SyncContent(body: Data("not json".utf8)), kind: .feed) == nil)
    }
}

// MARK: - Two devices

@MainActor
@Suite("Sync between devices")
struct SyncCoreTests {
    let zone = FakeCloudZone()
    let clock = TestClock(wall: start)

    private func device() -> FakeDevice { FakeDevice(zone: zone, clock: clock) }

    @Test func aNewFeedReachesTheOtherPhone() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)
        #expect(wife.store.feeds == [feed.id: feed])
        #expect(zone.saveCount == 1)
        // Nothing left to send on either phone, and the feed wasn't echoed back.
        #expect(try robby.core.scan().isEmpty)
        #expect(try wife.core.scan().isEmpty)
    }

    @Test func theBabyProfileAndPhotoSync() throws {
        let robby = device(), wife = device()
        let baby = BabyPayload(id: UUID(), name: "Ella", birthDate: start, createdAt: start)
        robby.store.babies[baby.id] = baby
        robby.store.photos[baby.id] = Data([9, 8, 7])
        try syncUntilQuiet(robby, wife)
        #expect(wife.store.babies[baby.id] == baby)
        #expect(wife.store.photos[baby.id] == Data([9, 8, 7]))

        wife.store.photos[baby.id] = nil
        clock.advance(by: 60)
        try syncUntilQuiet(wife, robby)
        #expect(robby.store.photos[baby.id] == nil)
    }

    @Test func anEditReachesTheOtherPhone() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)

        clock.advance(by: 60)
        wife.store.feeds[feed.id]?.notes = "Took it all"
        try syncUntilQuiet(wife, robby)
        #expect(robby.store.feeds[feed.id]?.notes == "Took it all")
        #expect(zone.saveCount == 2)
    }

    @Test func aDeleteReachesTheOtherPhone() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)

        robby.store.feeds[feed.id] = nil
        try syncUntilQuiet(robby, wife)
        #expect(wife.store.feeds.isEmpty)
        #expect(zone.records.isEmpty)
        #expect(robby.core.ledger.entries.isEmpty)
        #expect(wife.core.ledger.entries.isEmpty)
    }

    /// Both phones edit the same feed before either syncs: the later edit wins on both.
    @Test func theLaterEditWins() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)

        clock.advance(by: 60)
        robby.store.feeds[feed.id]?.notes = "Earlier edit"
        try robby.core.scan()
        clock.advance(by: 60)
        wife.store.feeds[feed.id]?.notes = "Later edit"
        try wife.core.scan()

        // The earlier edit reaches the server first; the later one must still win.
        try syncUntilQuiet(robby, wife)
        #expect(robby.store.feeds[feed.id]?.notes == "Later edit")
        #expect(wife.store.feeds[feed.id]?.notes == "Later edit")
    }

    /// Same, but the later edit reaches the server first: the earlier one must not overwrite it.
    @Test func anEarlierEditArrivingLateLoses() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)

        clock.advance(by: 60)
        robby.store.feeds[feed.id]?.notes = "Earlier edit"
        try robby.core.scan()
        clock.advance(by: 60)
        wife.store.feeds[feed.id]?.notes = "Later edit"

        try syncUntilQuiet(wife, robby)
        #expect(robby.store.feeds[feed.id]?.notes == "Later edit")
        #expect(wife.store.feeds[feed.id]?.notes == "Later edit")
    }

    /// One phone deletes a feed the other has an unsent edit for: the edit is kept.
    @Test func anUnsentEditSurvivesADeleteElsewhere() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)

        robby.store.feeds[feed.id] = nil
        try robby.sync()
        clock.advance(by: 60)
        wife.store.feeds[feed.id]?.notes = "Edited while offline"
        try syncUntilQuiet(wife, robby)
        #expect(wife.store.feeds[feed.id]?.notes == "Edited while offline")
        #expect(robby.store.feeds[feed.id]?.notes == "Edited while offline")
    }

    /// A delete made after another phone's edit removes the feed everywhere.
    @Test func aLaterDeleteBeatsAnEarlierEdit() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)

        clock.advance(by: 60)
        wife.store.feeds[feed.id]?.notes = "Edit"
        try wife.sync()
        clock.advance(by: 60)
        robby.store.feeds[feed.id] = nil
        try syncUntilQuiet(robby, wife)
        #expect(robby.store.feeds.isEmpty)
        #expect(wife.store.feeds.isEmpty)
    }

    /// Updating from the build that synced through SwiftData: both phones already hold the same
    /// feeds and both upload them. Nothing is duplicated, changed or sent twice.
    @Test func phonesThatAlreadyAgreeUploadOnce() throws {
        let robby = device(), wife = device()
        let feeds = (0..<20).map { bottle(at: start.addingTimeInterval(Double($0) * -3_600)) }
        for feed in feeds {
            robby.store.feeds[feed.id] = feed
            wife.store.feeds[feed.id] = feed
        }
        clock.advance(by: 86_400)
        try syncUntilQuiet(robby, wife)
        #expect(zone.saveCount == 20)
        #expect(robby.store.feeds == wife.store.feeds)
        #expect(robby.store.applyCount == 0)
        #expect(wife.store.applyCount == 0)
        // The feeds keep their own times, so they don't pose as fresh edits later.
        #expect(zone.records[feeds[3].key]?.changedAt == feeds[3].modifiedAt)
    }

    /// A parent joins the other's shared log: their feeds are merged in, and where both have the
    /// same feed the one edited last wins, not the one that happened to upload last.
    @Test func joiningASharedLogMergesBothHistories() throws {
        let robbyZone = FakeCloudZone()
        let robby = FakeDevice(zone: robbyZone, clock: clock)
        let wife = FakeDevice(zone: FakeCloudZone(), clock: clock)
        let shared = bottle(notes: "Old note")
        let hers = bottle(at: start.addingTimeInterval(-7_200))
        let his = bottle(at: start.addingTimeInterval(-3_600))
        robby.store.feeds = [shared.id: shared, his.id: his]
        wife.store.feeds = [shared.id: shared, hers.id: hers]
        try syncUntilQuiet(robby)
        try syncUntilQuiet(wife)

        clock.advance(by: 60)
        robby.store.feeds[shared.id]?.notes = "Robby's newer note"
        try syncUntilQuiet(robby)

        clock.advance(by: 3_600)
        wife.move(to: robbyZone)
        try syncUntilQuiet(wife, robby)
        #expect(Set(robby.store.feeds.keys) == [shared.id, his.id, hers.id])
        #expect(robby.store.feeds == wife.store.feeds)
        #expect(wife.store.feeds[shared.id]?.notes == "Robby's newer note")
    }

    /// Sharing ended: the partner keeps every feed and syncs them to their own iCloud again.
    @Test func leavingKeepsACopy() throws {
        let robbyZone = FakeCloudZone()
        let robby = FakeDevice(zone: robbyZone, clock: clock)
        let wife = FakeDevice(zone: robbyZone, clock: clock)
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)

        let ownZone = FakeCloudZone()
        wife.move(to: ownZone)
        try syncUntilQuiet(wife)
        #expect(wife.store.feeds == [feed.id: feed])
        #expect(ownZone.records[feed.key] != nil)
        // And the two logs are now separate.
        wife.store.feeds[feed.id] = nil
        try syncUntilQuiet(wife, robby)
        #expect(robby.store.feeds[feed.id] != nil)
    }

    @Test func theLedgerSurvivesARelaunch() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)
        try robby.relaunch()
        #expect(try robby.core.scan().isEmpty)

        // An edit made just before the app was closed is still found afterwards.
        clock.advance(by: 60)
        robby.store.feeds[feed.id]?.notes = "Before closing"
        try robby.relaunch()
        try syncUntilQuiet(robby, wife)
        #expect(wife.store.feeds[feed.id]?.notes == "Before closing")
    }

    /// A feed deleted while the app couldn't reach iCloud is still deleted after a relaunch.
    @Test func aDeleteSurvivesARelaunch() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)
        robby.store.feeds[feed.id] = nil
        try robby.core.scan()
        try robby.relaunch()
        try syncUntilQuiet(robby, wife)
        #expect(wife.store.feeds.isEmpty)
    }

    /// The record this phone saved over was deleted on the server meanwhile: it is sent again.
    @Test func aRecordTheServerLostIsSentAgain() throws {
        let robby = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby)
        zone.delete(feed.key)
        clock.advance(by: 60)
        robby.store.feeds[feed.id]?.notes = "Edit"
        try robby.core.scan()
        // Send without fetching first, so the phone hasn't heard about the delete.
        let record = try #require(try robby.core.outgoingRecord(for: feed.key))
        guard case .unknownItem = zone.save(record) else {
            Issue.record("Expected the server to have lost the record")
            return
        }
        robby.core.serverLost(feed.key)
        let again = try #require(try robby.core.outgoingRecord(for: feed.key))
        #expect(again.systemFields == nil)
        guard case .saved(let saved) = zone.save(again) else {
            Issue.record("Expected the save to go through")
            return
        }
        robby.core.didSave(saved)
        #expect(try robby.core.scan().isEmpty)
        #expect(zone.records[feed.key]?.content == robby.store.feeds[feed.id]?.content())
    }

    /// A store that can't keep every detail must not bounce the record back and forth forever.
    @Test func aLossyStoreDoesNotEcho() throws {
        let robby = device(), wife = device()
        wife.store.notesLimit = 3
        let feed = bottle(notes: "A long note")
        robby.store.feeds[feed.id] = feed
        try syncUntilQuiet(robby, wife)
        #expect(wife.store.feeds[feed.id]?.notes == "A l")
        #expect(robby.store.feeds[feed.id]?.notes == "A long note")
        #expect(zone.saveCount == 1)
    }

    /// Records from a newer build that this one can't read are left alone.
    @Test func unreadableRecordsAreSkipped() throws {
        let robby = device()
        let key = SyncKey(kind: .feed, id: UUID())
        let changed = try robby.core.receive(modifications: [
            SyncRecord(key: key, changedAt: start, content: SyncContent(body: Data("{}".utf8)), systemFields: Data([1])),
        ])
        #expect(changed == false)
        #expect(robby.store.feeds.isEmpty)
        #expect(try robby.core.scan().isEmpty)
    }

    /// If the store can't be written, nothing is recorded as received, so nothing is lost.
    @Test func aFailedWriteLeavesTheLedgerUntouched() throws {
        let robby = device(), wife = device()
        let feed = bottle()
        robby.store.feeds[feed.id] = feed
        try robby.sync()
        struct DiskFull: Error {}
        wife.store.failure = DiskFull()
        #expect(throws: DiskFull.self) { try wife.fetch() }
        #expect(wife.core.ledger.entries.isEmpty)
    }

    /// A feed logged while the timer was still open elsewhere keeps both phones' work: edits on
    /// different feeds never conflict.
    @Test func editsToDifferentFeedsBothLand() throws {
        let robby = device(), wife = device()
        let first = bottle(), second = bottle(at: start.addingTimeInterval(600))
        robby.store.feeds = [first.id: first, second.id: second]
        try syncUntilQuiet(robby, wife)
        clock.advance(by: 60)
        robby.store.feeds[first.id]?.notes = "From Robby"
        wife.store.feeds[second.id]?.notes = "From his wife"
        try syncUntilQuiet(robby, wife)
        #expect(robby.store.feeds == wife.store.feeds)
        #expect(robby.store.feeds[first.id]?.notes == "From Robby")
        #expect(robby.store.feeds[second.id]?.notes == "From his wife")
    }
}

enum PinnedFingerprints {
    static let feed: Int64 = 7_465_518_140_352_207_749
    static let baby: Int64 = -703_567_800_009_309_635
}
