import Foundation

/// Remembers which running feeds were started on another phone and arrived through sync, so
/// "Still feeding?" only asks on the phone the timer was started on (docs/ICLOUD_SYNC.md).
///
/// Kept beside the store, not in it: it is about this phone only and must not sync.
struct FeedOrigins: Sendable {
    private static let key = "feedsStartedElsewhere"
    /// A handful is plenty: only a feed that is still running is ever asked about.
    private static let limit = 20

    // `UserDefaults` is thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func markStartedElsewhere(_ id: UUID) {
        var ids = defaults.stringArray(forKey: Self.key) ?? []
        guard !ids.contains(id.uuidString) else { return }
        ids.append(id.uuidString)
        defaults.set(Array(ids.suffix(Self.limit)), forKey: Self.key)
    }

    func wasStartedHere(_ id: UUID) -> Bool {
        !(defaults.stringArray(forKey: Self.key) ?? []).contains(id.uuidString)
    }
}
