import Foundation
import NewbeeKit
import SwiftData

/// Schema version 4: V3 plus `PumpDetails.isTotalOnly`, for pumping logged as one total without
/// a left/right split. See docs/DATA_MODEL.md.
///
/// Keep the CloudKit-friendly rules from V3 (every property has a default or is optional, every
/// relationship is optional, no unique constraints, enums stored as raw strings). Sync carries
/// models as `FeedPayload`s, so a change here also goes into the payload, not `schema.ckdb`.
enum NewbeeSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Baby.self, FeedingSession.self, FeedingSegment.self, BottleDetails.self, PumpDetails.self]
    }

    @Model
    final class Baby {
        var id: UUID = UUID()
        var name: String = ""
        var birthDate: Date?
        var createdAt: Date = Date()
        /// The profile photo as a small JPEG (see `BabyPhotoStore`). Kept outside the SQLite file
        /// and synced to iCloud as an asset.
        @Attribute(.externalStorage) var photoData: Data?

        /// Nullify, not cascade: when two devices each made a `Baby` before they first synced, one
        /// is merged into the other (`BabyMerge`). A cascade would delete feeds that another device
        /// hasn't moved to the kept baby yet. Feeds are always deleted explicitly anyway.
        @Relationship(deleteRule: .nullify, inverse: \FeedingSession.baby)
        var sessions: [FeedingSession]? = []

        init(id: UUID = UUID(), name: String = "", birthDate: Date? = nil, createdAt: Date = .now) {
            self.id = id
            self.name = name
            self.birthDate = birthDate
            self.createdAt = createdAt
        }
    }

    @Model
    final class FeedingSession {

        var id: UUID = UUID()
        var baby: Baby?
        var kindRaw: String = FeedingKind.breast.rawValue
        var statusRaw: String = SessionStatus.completed.rawValue
        var startedAt: Date = Date()
        var endedAt: Date?
        var timeZoneID: String = TimeZone.current.identifier
        var notes: String = ""
        var sourceRaw: String = EntrySource.timer.rawValue
        var needsReview: Bool = false
        /// When the parent last answered "Keep going" on the recovery sheet.
        var recoveryAcknowledgedAt: Date?
        var revision: Int = 0
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \FeedingSegment.session)
        var segments: [FeedingSegment]? = []

        @Relationship(deleteRule: .cascade, inverse: \BottleDetails.session)
        var bottle: BottleDetails?

        @Relationship(deleteRule: .cascade, inverse: \PumpDetails.session)
        var pump: PumpDetails?

        init(
            id: UUID = UUID(),
            kind: FeedingKind,
            status: SessionStatus,
            startedAt: Date,
            timeZoneID: String = TimeZone.current.identifier,
            source: EntrySource = .timer
        ) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.statusRaw = status.rawValue
            self.startedAt = startedAt
            self.timeZoneID = timeZoneID
            self.sourceRaw = source.rawValue
        }

        var kind: FeedingKind {
            get { FeedingKind(rawValue: kindRaw) ?? .breast }
            set { kindRaw = newValue.rawValue }
        }

        var status: SessionStatus {
            get { SessionStatus(rawValue: statusRaw) ?? .completed }
            set { statusRaw = newValue.rawValue }
        }

        var source: EntrySource {
            get { EntrySource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }

        /// Segments sorted by start time.
        var orderedSegments: [FeedingSegment] {
            (segments ?? []).sorted { $0.startedAt < $1.startedAt }
        }
    }

    @Model
    final class FeedingSegment {

        var id: UUID = UUID()
        var session: FeedingSession?
        var sideRaw: String = Side.left.rawValue
        var startedAt: Date = Date()
        var endedAt: Date?
        var startMonotonic: Double?
        var startBootID: String?

        init(
            id: UUID = UUID(),
            side: Side,
            startedAt: Date,
            endedAt: Date? = nil,
            startMonotonic: Double? = nil,
            startBootID: String? = nil
        ) {
            self.id = id
            self.sideRaw = side.rawValue
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.startMonotonic = startMonotonic
            self.startBootID = startBootID
        }

        var side: Side {
            get { Side(rawValue: sideRaw) ?? .left }
            set { sideRaw = newValue.rawValue }
        }
    }

    @Model
    final class BottleDetails {
        var session: FeedingSession?
        var contentsRaw: String = BottleContents.breastMilk.rawValue
        /// Canonical amount in milliliters.
        var amountML: Double = 0
        /// The unit the parent typed, so editing shows their original entry.
        var enteredUnitRaw: String = VolumeUnit.milliliters.rawValue
        var durationSeconds: Double?

        init(contents: BottleContents, amountML: Double, enteredUnit: VolumeUnit, durationSeconds: Double? = nil) {
            self.contentsRaw = contents.rawValue
            self.amountML = amountML
            self.enteredUnitRaw = enteredUnit.rawValue
            self.durationSeconds = durationSeconds
        }

        var contents: BottleContents {
            get { BottleContents(rawValue: contentsRaw) ?? .other }
            set { contentsRaw = newValue.rawValue }
        }

        var enteredUnit: VolumeUnit {
            get { VolumeUnit(rawValue: enteredUnitRaw) ?? .milliliters }
            set { enteredUnitRaw = newValue.rawValue }
        }
    }

    /// A pumping session (`kind = pump`): amounts per side, or one total. Timing is the session's start and
    /// end plus an optional entered duration, like `BottleDetails`.
    @Model
    final class PumpDetails {
        var session: FeedingSession?
        /// Canonical amounts in milliliters.
        var leftML: Double = 0
        var rightML: Double = 0
        /// The unit the parent typed, so editing shows their original entry.
        var enteredUnitRaw: String = VolumeUnit.milliliters.rawValue
        var durationSeconds: Double?
        /// Logged as one total without a left/right split; the total is stored half on each side
        /// (`PumpEntry.isTotalOnly`). `false` for every entry from before V4.
        var isTotalOnly: Bool = false

        init(leftML: Double, rightML: Double, enteredUnit: VolumeUnit, durationSeconds: Double? = nil, isTotalOnly: Bool = false) {
            self.leftML = leftML
            self.rightML = rightML
            self.enteredUnitRaw = enteredUnit.rawValue
            self.durationSeconds = durationSeconds
            self.isTotalOnly = isTotalOnly
        }

        var enteredUnit: VolumeUnit {
            get { VolumeUnit(rawValue: enteredUnitRaw) ?? .milliliters }
            set { enteredUnitRaw = newValue.rawValue }
        }
    }
}

extension NewbeeSchemaV4.FeedingSession {
    /// Deletes this session together with its segments, bottle details and pump details.
    ///
    /// The `.cascade` delete rule proved unreliable (CI on iOS 17 showed children surviving a
    /// parent delete), so children are deleted explicitly. Always delete sessions through this method.
    func deleteWithChildren(from context: ModelContext) {
        for segment in segments ?? [] {
            context.delete(segment)
        }
        if let bottle {
            context.delete(bottle)
        }
        if let pump {
            context.delete(pump)
        }
        context.delete(self)
    }
}

// The app always works with the latest schema through these aliases.
typealias Baby = NewbeeSchemaV4.Baby
typealias FeedingSession = NewbeeSchemaV4.FeedingSession
typealias FeedingSegment = NewbeeSchemaV4.FeedingSegment
typealias BottleDetails = NewbeeSchemaV4.BottleDetails
typealias PumpDetails = NewbeeSchemaV4.PumpDetails

/// Every schema change adds a version and a migration stage here.
enum NewbeeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NewbeeSchemaV1.self, NewbeeSchemaV2.self, NewbeeSchemaV3.self, NewbeeSchemaV4.self] }

    /// V1 → V2 only adds the `PumpDetails` entity and an optional relationship to it, and V2 → V3
    /// only adds the optional `Baby.photoData` (and changes a delete rule, which isn't stored), and
    /// V3 → V4 only adds `PumpDetails.isTotalOnly` with a default of `false`, so
    /// SwiftData migrates the store in place without touching existing rows.
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: NewbeeSchemaV1.self, toVersion: NewbeeSchemaV2.self),
            .lightweight(fromVersion: NewbeeSchemaV2.self, toVersion: NewbeeSchemaV3.self),
            .lightweight(fromVersion: NewbeeSchemaV3.self, toVersion: NewbeeSchemaV4.self),
        ]
    }
}
