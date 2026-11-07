import Foundation
import NewbeeKit
import SwiftData

// Mapping between SwiftData models and NewbeeKit value types. `@Model` objects never leave the
// persistence layer; everything above it works with `SessionSnapshot`.

extension FeedingSession {
    /// A value copy of this session and its segments, ordered by start time.
    var sessionSnapshot: SessionSnapshot {
        SessionSnapshot(
            id: id,
            status: status,
            segments: (segments ?? [])
                .sorted { ($0.startedAt, $0.endedAt ?? .distantFuture) < ($1.startedAt, $1.endedAt ?? .distantFuture) }
                .map(\.valueSegment),
            startedAt: startedAt,
            endedAt: endedAt,
            revision: revision,
            timeZoneID: timeZoneID,
            source: source,
            needsReview: needsReview,
            notes: notes,
            recoveryAcknowledgedAt: recoveryAcknowledgedAt
        )
    }

    /// Makes this model match `snapshot`: updates fields, updates segments in place by ID,
    /// inserts new segments and deletes segments the snapshot no longer has.
    func apply(_ snapshot: SessionSnapshot, in context: ModelContext) {
        status = snapshot.status
        startedAt = snapshot.startedAt
        endedAt = snapshot.endedAt
        revision = snapshot.revision
        timeZoneID = snapshot.timeZoneID
        source = snapshot.source
        needsReview = snapshot.needsReview
        notes = snapshot.notes
        recoveryAcknowledgedAt = snapshot.recoveryAcknowledgedAt

        var existing = Dictionary((segments ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var updated: [FeedingSegment] = []
        for segment in snapshot.segments {
            if let model = existing.removeValue(forKey: segment.id) {
                model.update(from: segment)
                updated.append(model)
            } else {
                let model = FeedingSegment(
                    id: segment.id,
                    side: segment.side,
                    startedAt: segment.start,
                    endedAt: segment.end,
                    startMonotonic: segment.startMonotonic,
                    startBootID: segment.startBootID
                )
                context.insert(model)
                updated.append(model)
            }
        }
        for orphan in existing.values {
            context.delete(orphan)
        }
        segments = updated
    }
}

extension FeedingSegment {
    var valueSegment: Segment {
        Segment(
            id: id,
            side: side,
            start: startedAt,
            end: endedAt,
            startMonotonic: startMonotonic,
            startBootID: startBootID
        )
    }

    func update(from segment: Segment) {
        side = segment.side
        startedAt = segment.start
        endedAt = segment.end
        startMonotonic = segment.startMonotonic
        startBootID = segment.startBootID
    }
}
