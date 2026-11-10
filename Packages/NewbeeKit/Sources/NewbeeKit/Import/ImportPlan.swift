import Foundation

/// What an import will add, after leaving out rows Newbee already has.
///
/// A row is a duplicate when Newbee (or an earlier row of the same file) already has an entry of
/// the same kind that starts in the same minute. Huckleberry records minutes only, so this catches
/// both re-importing a file and a feed logged in both apps.
public struct ImportPlan: Sendable, Hashable {
    /// What will be saved, oldest first.
    public var records: [ImportedRecord]
    /// Rows left out because Newbee already has them.
    public var duplicates: Int
    /// Rows of types Newbee doesn't track, by type, largest first.
    public var unsupported: [SkippedType] {
        unsupportedByType.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { SkippedType(type: $0.key, count: $0.value) }
    }
    public var unsupportedByType: [String: Int]
    public var problems: [ImportProblem]

    public init(export: HuckleberryExport, existing: some Sequence<ImportKey>) {
        var seen = Set(existing)
        var records: [ImportedRecord] = []
        var duplicates = 0
        for record in export.records.sorted(by: { $0.start < $1.start }) {
            if seen.insert(ImportKey(record)).inserted {
                records.append(record)
            } else {
                duplicates += 1
            }
        }
        self.records = records
        self.duplicates = duplicates
        self.unsupportedByType = export.unsupported
        self.problems = export.problems
    }

    public var breastCount: Int { records.count { $0.kind == .breast } }
    public var bottleCount: Int { records.count { $0.kind == .bottle } }
    public var pumpCount: Int { records.count { $0.kind == .pump } }
    public var unsupportedCount: Int { unsupportedByType.values.reduce(0, +) }

    /// First and last start time of what will be saved.
    public var dateRange: ClosedRange<Date>? {
        guard let first = records.first?.start, let last = records.last?.start else { return nil }
        return first...last
    }

    public var isEmpty: Bool { records.isEmpty }
}

/// A kind of row Newbee doesn't track, and how many the file had.
public struct SkippedType: Sendable, Hashable, Identifiable {
    public var type: String
    public var count: Int
    public var id: String { type }
}

/// Identifies "the same entry" across apps: its kind and the minute it started.
public struct ImportKey: Sendable, Hashable {
    public var kind: FeedingKind
    /// Whole minutes since 1970, so 14:05:00 and 14:05:50 match.
    public var minute: Int64

    public init(kind: FeedingKind, start: Date) {
        self.kind = kind
        self.minute = Int64((start.timeIntervalSince1970 / 60).rounded(.down))
    }

    public init(_ record: ImportedRecord) {
        self.init(kind: record.kind, start: record.start)
    }
}
