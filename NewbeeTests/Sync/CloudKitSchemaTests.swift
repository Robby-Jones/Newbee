import CloudKit
import Foundation
import NewbeeKit
import Testing
@testable import Newbee

/// `cloudkit/schema.ckdb` must declare every record type and field sync writes. TestFlight and
/// App Store builds only sync with the production schema, so a field missing there stops sync on
/// every phone (docs/ICLOUD_SYNC.md).
@Suite("CloudKit schema")
struct CloudKitSchemaTests {
    /// Record type → field → type, for every type the schema file declares.
    static func declaredFields() throws -> [String: [String: String]] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "cloudkit/schema.ckdb")
        let text = try String(contentsOf: url, encoding: .utf8)
        var types: [String: [String: String]] = [:]
        var recordType: String?
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") { continue }
            let words = line.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\",")) }
            if line.hasPrefix("RECORD TYPE "), words.count >= 3 {
                recordType = words[2]
                types[words[2]] = [:]
            } else if line.hasPrefix(");") {
                recordType = nil
            } else if let recordType, words.count >= 2, !line.hasPrefix("GRANT") {
                types[recordType]?[words[0]] = words[1]
            }
        }
        return types
    }

    @Test func everySyncedRecordTypeIsDeclared() throws {
        let declared = try Self.declaredFields()
        for kind in SyncRecordKind.allCases {
            let fields = try #require(declared[kind.rawValue], "Add RECORD TYPE \(kind.rawValue) to cloudkit/schema.ckdb")
            for (name, type) in CloudRecordCoding.schemaFields(for: kind) {
                #expect(fields[name] == type, "\(kind.rawValue).\(name) should be \(type) in cloudkit/schema.ckdb")
            }
        }
    }

    /// Production refuses to save a share until CloudKit's own share type has been deployed.
    @Test func theShareTypeIsDeclared() throws {
        let declared = try Self.declaredFields()
        let share = try #require(declared[CKRecord.SystemType.share])
        #expect(share["cloudkit.title"] == "STRING")
    }

    /// Types that reached production can't be deleted, so they must stay in the file: importing a
    /// schema without them would try to remove them.
    @Test func typesFromTheFirstSyncVersionStay() throws {
        let declared = try Self.declaredFields()
        for name in ["CD_Baby", "CD_FeedingSession", "CD_FeedingSegment", "CD_BottleDetails", "CD_PumpDetails", "Users"] {
            #expect(declared[name] != nil, "\(name) must stay in cloudkit/schema.ckdb")
        }
    }
}
