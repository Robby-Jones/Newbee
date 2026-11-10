import Foundation
import NewbeeKit
import SwiftData

/// Schema version 2: V1 plus `PumpDetails` for pumping sessions. See docs/DATA_MODEL.md.
///
/// Same CloudKit-ready rules as V1 (ADR-005): every property has a default or is optional, every
/// relationship is optional, no unique constraints, enums stored as raw strings.
enum NewbeeSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Baby.self, FeedingSession.self, FeedingSegment.self, BottleDetails.self, PumpDetails.self]
    }

    @Model
    final class Baby {
        var id: UUID = UUID()
        var name: String = ""
        var birthDate: Date?
        var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \FeedingSession.baby)
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

    /// A pumping session (`kind = pump`): amounts per side. Timing is the session's start and
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

        init(leftML: Double, rightML: Double, enteredUnit: VolumeUnit, durationSeconds: Double? = nil) {
            self.leftML = leftML
            self.rightML = rightML
            self.enteredUnitRaw = enteredUnit.rawValue
            self.durationSeconds = durationSeconds
        }

        var enteredUnit: VolumeUnit {
            get { VolumeUnit(rawValue: enteredUnitRaw) ?? .milliliters }
            set { enteredUnitRaw = newValue.rawValue }
        }
    }
}
