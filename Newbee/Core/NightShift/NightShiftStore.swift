import Foundation
import NewbeeKit
import Observation

/// Tonight's shift as this phone knows it (docs/NIGHT_SHIFT.md).
///
/// The shift is one small record that syncs through the shared log like a feed does
/// (`SwiftDataSyncStore`). It is kept in `UserDefaults`, not in the SwiftData store: it is a
/// single value, and a new model would mean a schema migration.
@MainActor
@Observable
final class NightShiftStore {
    private enum Key {
        static let shift = "nightShift.shift"
        static let me = "nightShift.me"
        static let dismissedSummary = "nightShift.dismissedSummary"
        static let earlyEndNotified = "nightShift.earlyEndNotified"
    }

    /// How long after a shift was ended early its summary is still worth a notification.
    private static let earlyEndWindow: TimeInterval = 30 * 60

    private(set) var shift: NightShift?
    /// This parent's ID, the same on all their devices (their iCloud user record name). `nil`
    /// until iCloud has been asked once.
    private(set) var me: String?
    /// `startedAt` of the shift whose "While you slept" card the parent closed.
    private(set) var dismissedSummaryStart: Date?

    /// The shift changed, here or on the other phone: reminders need another look.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    /// The shift changed on this phone: it needs to sync.
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shift = defaults.data(forKey: Key.shift).flatMap { try? JSONDecoder().decode(NightShift.self, from: $0) }
        me = defaults.string(forKey: Key.me)
        dismissedSummaryStart = defaults.object(forKey: Key.dismissedSummary) as? Date
    }

    /// A change made on this phone: start, take over, end, or `nil` for "Delete all data".
    func set(_ shift: NightShift?) {
        guard shift != self.shift else { return }
        save(shift)
        onLocalChange?()
        onChange?()
    }

    /// A change that arrived from the other phone.
    func applyFromSync(_ shift: NightShift?) {
        guard shift != self.shift else { return }
        save(shift)
        onChange?()
    }

    func setMe(_ id: String?) {
        guard id != me else { return }
        me = id
        defaults.set(id, forKey: Key.me)
        onChange?()
    }

    /// Whether `shift` was the partner's, was ended early in the last half hour, and hasn't been
    /// announced on this phone yet.
    func shouldNotifyEarlyEnd(of shift: NightShift, me: String, at now: Date) -> Bool {
        guard shift.onDuty != me, let endedAt = shift.endedAt, endedAt < shift.endsAt,
              now >= endedAt, now < endedAt.addingTimeInterval(Self.earlyEndWindow) else { return false }
        return defaults.object(forKey: Key.earlyEndNotified) as? Date != shift.startedAt
    }

    func markEarlyEndNotified(_ shift: NightShift) {
        defaults.set(shift.startedAt, forKey: Key.earlyEndNotified)
    }

    func dismissSummary(of shift: NightShift) {
        dismissedSummaryStart = shift.startedAt
        defaults.set(shift.startedAt, forKey: Key.dismissedSummary)
    }

    private func save(_ shift: NightShift?) {
        self.shift = shift
        if let shift, let data = try? JSONEncoder().encode(shift) {
            defaults.set(data, forKey: Key.shift)
        } else {
            defaults.removeObject(forKey: Key.shift)
        }
    }
}
