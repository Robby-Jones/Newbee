import CloudKit
import Foundation
import NewbeeKit

/// How synced items are stored in CloudKit (docs/ICLOUD_SYNC.md, `cloudkit/schema.ckdb`).
///
/// Every record type has the same few fields: the item as JSON in `payload`, when it last changed,
/// and the payload format. New properties go inside the JSON, so they never need a schema deploy.
enum CloudRecordCoding {
    enum Field {
        static let payload = "payload"
        /// The baby's photo, on `Baby` records only.
        static let photo = "photo"
        static let changedAt = "changedAt"
        static let version = "v"
    }

    /// The payload format this build writes.
    static let version: Int64 = 1

    /// The record type and its fields, as the schema file must declare them.
    static func schemaFields(for kind: SyncRecordKind) -> [String: String] {
        var fields = [Field.payload: "BYTES", Field.changedAt: "TIMESTAMP", Field.version: "INT64"]
        if kind == .baby {
            fields[Field.photo] = "BYTES"
        }
        return fields
    }

    static func recordID(for key: SyncKey, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: key.id, zoneID: zoneID)
    }

    /// The CloudKit record to save for `record`. It starts from the server's last known copy when
    /// there is one, so the save carries the change tag the server expects.
    static func cloudRecord(for record: SyncRecord, in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = recordID(for: record.key, in: zoneID)
        let type = record.key.kind.rawValue
        var known = record.systemFields.flatMap(decodeSystemFields)
        if known?.recordID != recordID || known?.recordType != type {
            known = nil
        }
        let cloud = known ?? CKRecord(recordType: type, recordID: recordID)
        cloud[Field.payload] = record.content.body
        cloud[Field.changedAt] = record.changedAt
        cloud[Field.version] = version
        if record.key.kind == .baby {
            if let photo = record.content.attachment {
                cloud[Field.photo] = photo
            } else {
                cloud[Field.photo] = nil
            }
        }
        return cloud
    }

    /// `nil` for records that aren't Newbee's (the share itself) or have no payload.
    static func syncRecord(from cloud: CKRecord) -> SyncRecord? {
        guard let kind = SyncRecordKind(rawValue: cloud.recordType),
              let body = cloud[Field.payload] as? Data else { return nil }
        return SyncRecord(
            key: SyncKey(kind: kind, id: cloud.recordID.recordName),
            changedAt: cloud[Field.changedAt] as? Date ?? cloud.modificationDate ?? .distantPast,
            content: SyncContent(body: body, attachment: cloud[Field.photo] as? Data),
            systemFields: encodeSystemFields(cloud)
        )
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }
}
