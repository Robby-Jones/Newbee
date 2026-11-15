import CloudKit
import Foundation
import Observation

/// iCloud sync as Settings shows it, and the signal that changes from another phone have arrived
/// (docs/ICLOUD_SYNC.md). `CloudSyncEngine` reports to it; it does no syncing itself.
@MainActor
@Observable
final class CloudSyncMonitor {
    enum Status: Equatable {
        /// This build or run doesn't sync (tests, previews).
        case unavailable
        /// The parent hasn't turned on "Sync with iCloud", or turned it off.
        case off
        /// Asking iCloud whether the parent is signed in.
        case checking
        /// No iCloud account on this device, or iCloud is turned off for Newbee.
        case signedOut
        /// iCloud is restricted (Screen Time, a managed device).
        case restricted
        /// iCloud can't be reached right now.
        case temporarilyUnavailable
        case syncing
        /// Something couldn't be sent; Newbee keeps trying.
        case failed(String)
        /// Everything that was asked for has synced.
        case upToDate(Date?)
    }

    /// The iCloud container, or `nil` when this run doesn't sync.
    let containerID: String?
    private(set) var status: Status
    /// Whether "Sync with iCloud" is on (`CloudSyncSwitch`).
    private(set) var isEnabled: Bool
    /// False once iCloud says this device has no account, or iCloud is restricted. Known even with
    /// sync off, so Settings can tell what turning it on would do.
    private(set) var hasICloudAccount = true
    /// Goes up by one each time changes from iCloud were written to the store. The app observes
    /// it to refresh what isn't driven by `@Query`: the timer, Live Activity, reminders and photo.
    private(set) var importCount = 0
    /// Runs after each import, also when iOS woke the app in the background for it.
    @ObservationIgnored var onImport: (@MainActor () -> Void)?

    @ObservationIgnored private var accountStatus: CKAccountStatus?
    @ObservationIgnored private var inFlight = Set<UUID>()
    @ObservationIgnored private var sendError: String?
    @ObservationIgnored private var lastSuccess: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(containerID: String?, isEnabled: Bool = true) {
        self.containerID = containerID
        self.isEnabled = isEnabled
        status = containerID == nil ? .unavailable : (isEnabled ? .checking : .off)
    }

    /// "Sync with iCloud" was turned on or off. Whatever was running is forgotten: a stopped
    /// engine never reports its end.
    func setEnabled(_ isOn: Bool) {
        isEnabled = isOn
        inFlight = []
        sendError = nil
        updateStatus()
    }

    /// Starts watching the iCloud account, also while sync is off. Call once.
    func start() {
        guard let containerID, observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
            // The monitor lives as long as the app (`AppDependencies.shared`).
            Task { @MainActor in await self.refreshAccountStatus() }
        })
        Task { await refreshAccountStatus(containerID: containerID) }
    }

    func refreshAccountStatus() async {
        guard let containerID else { return }
        await refreshAccountStatus(containerID: containerID)
    }

    private func refreshAccountStatus(containerID: String) async {
        accountStatus = try? await CKContainer(identifier: containerID).accountStatus()
        hasICloudAccount = accountStatus != .noAccount && accountStatus != .restricted
        updateStatus()
    }

    /// A fetch or a send started or finished.
    func handle(_ change: CloudSyncEvent) {
        if change.finished {
            inFlight.remove(change.id)
            if change.succeeded {
                lastSuccess = change.endDate ?? .now
            }
        } else {
            inFlight.insert(change.id)
        }
        updateStatus()
    }

    /// What is keeping changes from being sent, or `nil` once they go through.
    func setSendError(_ message: String?) {
        sendError = message
        updateStatus()
    }

    /// Changes from iCloud were written to the store.
    func didImportChanges() {
        importCount += 1
        onImport?()
    }

    private func updateStatus() {
        guard containerID != nil else { return }
        guard isEnabled else {
            status = .off
            return
        }
        switch accountStatus {
        case .noAccount:
            status = .signedOut
            return
        case .restricted:
            status = .restricted
            return
        case .temporarilyUnavailable:
            status = .temporarilyUnavailable
            return
        default:
            break
        }
        if !inFlight.isEmpty {
            status = .syncing
        } else if let sendError {
            status = .failed(sendError)
        } else if accountStatus == nil && lastSuccess == nil {
            status = .checking
        } else {
            status = .upToDate(lastSuccess)
        }
    }
}

/// One fetch from iCloud (`import`) or send to it (`export`), as it starts and as it ends.
struct CloudSyncEvent: Sendable {
    enum Kind: Sendable { case `import`, export }
    let id: UUID
    let kind: Kind
    let finished: Bool
    let succeeded: Bool
    let endDate: Date?

    /// CloudKit's own descriptions are long and technical; the common ones get plain words.
    static func message(for error: Error) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .quotaExceeded:
                return String(localized: "Your iCloud storage is full.")
            case .networkUnavailable, .networkFailure:
                return String(localized: "No internet connection.")
            case .notAuthenticated:
                return String(localized: "Sign in to iCloud to sync.")
            case .permissionFailure:
                return String(localized: "You don't have permission to change this shared log.")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
