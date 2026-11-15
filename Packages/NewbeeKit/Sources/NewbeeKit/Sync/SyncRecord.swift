import Foundation

/// What a synced record holds. The raw value is the CloudKit record type; never rename one.
public enum SyncRecordKind: String, Codable, Sendable, CaseIterable, Hashable {
    case baby = "Baby"
    case feed = "Feed"
}

/// Identifies one synced item on every device: its kind and its ID (the record name).
public struct SyncKey: Codable, Sendable, Hashable, CustomStringConvertible {
    public var kind: SyncRecordKind
    public var id: String

    public init(kind: SyncRecordKind, id: String) {
        self.kind = kind
        self.id = id
    }

    public init(kind: SyncRecordKind, id: UUID) {
        self.init(kind: kind, id: id.uuidString)
    }

    public var description: String { "\(kind.rawValue)/\(id)" }
}

/// What a record carries between devices: the item as JSON, plus bytes that are better kept out
/// of JSON (the baby's photo).
public struct SyncContent: Sendable, Hashable {
    public var body: Data
    public var attachment: Data?

    public init(body: Data, attachment: Data? = nil) {
        self.body = body
        self.attachment = attachment
    }
}

/// One record as the server holds it, or as a device is about to send it.
public struct SyncRecord: Sendable, Hashable {
    public var key: SyncKey
    /// When the content was last changed, on whichever device changed it. The newer change wins
    /// when two devices changed the same item.
    public var changedAt: Date
    public var content: SyncContent
    /// The server's own bookkeeping for the record (CloudKit's archived system fields). A save
    /// must carry the newest one, or the server reports a conflict.
    public var systemFields: Data?

    public init(key: SyncKey, changedAt: Date, content: SyncContent, systemFields: Data? = nil) {
        self.key = key
        self.changedAt = changedAt
        self.content = content
        self.systemFields = systemFields
    }
}

/// An item that syncs, in the form it travels in.
///
/// Rules for changing a payload once it has shipped (records written by old builds stay around):
/// only add properties, make them optional, and never rename or remove one. A `nil` optional
/// isn't encoded, so old records keep their fingerprint.
public protocol SyncPayload: Codable, Sendable {
    static var kind: SyncRecordKind { get }
    var key: SyncKey { get }
}

extension SyncPayload {
    /// The record content for this payload. Keys are sorted so the same payload always gives the
    /// same bytes.
    public func content(attachment: Data? = nil) -> SyncContent {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Payloads are plain values that always encode.
        let body = (try? encoder.encode(self)) ?? Data()
        return SyncContent(body: body, attachment: attachment)
    }

    /// `nil` when the content isn't a payload this build can read (damaged, or a future format).
    public static func decode(_ content: SyncContent) -> Self? {
        try? JSONDecoder().decode(Self.self, from: content.body)
    }

    public func fingerprint(attachment: Data? = nil) -> Int64 {
        Fingerprint.of(self, attachment: attachment)
    }
}

/// The baby profile. The photo travels as the record's attachment.
public struct BabyPayload: SyncPayload, Hashable {
    public static let kind = SyncRecordKind.baby

    public var id: UUID
    public var name: String
    public var birthDate: Date?
    public var createdAt: Date

    public init(id: UUID, name: String, birthDate: Date?, createdAt: Date) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.createdAt = createdAt
    }

    public var key: SyncKey { SyncKey(kind: .baby, id: id) }
}

/// One feed or pumping session with everything that belongs to it: its segments and its bottle or
/// pump details. Syncing them as one record means a feed always arrives whole.
///
/// Enums travel as their raw strings, so a value added by a newer build passes through an older
/// one untouched. Which baby the feed belongs to isn't included: Newbee has one baby profile, and
/// every device attaches feeds to it.
public struct FeedPayload: SyncPayload, Hashable {
    public static let kind = SyncRecordKind.feed

    public struct Segment: Codable, Sendable, Hashable {
        public var id: UUID
        public var side: String
        public var startedAt: Date
        public var endedAt: Date?
        public var startMonotonic: Double?
        public var startBootID: String?

        public init(id: UUID, side: String, startedAt: Date, endedAt: Date?, startMonotonic: Double?, startBootID: String?) {
            self.id = id
            self.side = side
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.startMonotonic = startMonotonic
            self.startBootID = startBootID
        }
    }

    public struct Bottle: Codable, Sendable, Hashable {
        public var contents: String
        public var amountML: Double
        public var enteredUnit: String
        public var durationSeconds: Double?

        public init(contents: String, amountML: Double, enteredUnit: String, durationSeconds: Double?) {
            self.contents = contents
            self.amountML = amountML
            self.enteredUnit = enteredUnit
            self.durationSeconds = durationSeconds
        }
    }

    public struct Pump: Codable, Sendable, Hashable {
        public var leftML: Double
        public var rightML: Double
        public var enteredUnit: String
        public var durationSeconds: Double?

        public init(leftML: Double, rightML: Double, enteredUnit: String, durationSeconds: Double?) {
            self.leftML = leftML
            self.rightML = rightML
            self.enteredUnit = enteredUnit
            self.durationSeconds = durationSeconds
        }
    }

    public var id: UUID
    public var kind: String
    public var status: String
    public var startedAt: Date
    public var endedAt: Date?
    public var timeZoneID: String
    public var notes: String
    public var source: String
    public var needsReview: Bool
    public var recoveryAcknowledgedAt: Date?
    public var revision: Int
    public var createdAt: Date
    public var modifiedAt: Date
    /// Always in `Segment.inOrder`, so two devices holding the same segments agree on the bytes.
    public var segments: [Segment]
    public var bottle: Bottle?
    public var pump: Pump?

    public init(
        id: UUID,
        kind: String,
        status: String,
        startedAt: Date,
        endedAt: Date?,
        timeZoneID: String,
        notes: String,
        source: String,
        needsReview: Bool,
        recoveryAcknowledgedAt: Date?,
        revision: Int,
        createdAt: Date,
        modifiedAt: Date,
        segments: [Segment],
        bottle: Bottle?,
        pump: Pump?
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZoneID = timeZoneID
        self.notes = notes
        self.source = source
        self.needsReview = needsReview
        self.recoveryAcknowledgedAt = recoveryAcknowledgedAt
        self.revision = revision
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.segments = segments.sorted(by: Segment.inOrder)
        self.bottle = bottle
        self.pump = pump
    }

    public var key: SyncKey { SyncKey(kind: .feed, id: id) }
}

extension FeedPayload.Segment {
    /// By start time; the ID breaks ties so the order never depends on the device.
    public static func inOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public enum SyncCodec {
    /// The fingerprint a device would compute for an item holding `content`, or `nil` when this
    /// build can't read it. Computed from the decoded payload, not the JSON bytes, so it doesn't
    /// depend on how any device formats JSON.
    public static func fingerprint(of content: SyncContent, kind: SyncRecordKind) -> Int64? {
        switch kind {
        case .baby: BabyPayload.decode(content)?.fingerprint(attachment: content.attachment)
        case .feed: FeedPayload.decode(content)?.fingerprint()
        }
    }
}
