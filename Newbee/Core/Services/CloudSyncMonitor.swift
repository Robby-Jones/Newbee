import CloudKit
import CoreData
import Foundation
import Observation

/// Watches iCloud sync for the Settings status row, and tells the app when changes from another
/// device have arrived (docs/ICLOUD_SYNC.md).
///
/// SwiftData syncs through Core Data's CloudKit mirroring, which reports each setup, import and
/// export as an `NSPersistentCloudKitContainer.Event`.
@MainActor
@Observable
final class CloudSyncMonitor {
    enum Status: Equatable {
        /// This build or run doesn't sync (tests, previews).
        case unavailable
        /// The store couldn't be opened with iCloud, so it stays on this device for now.
        case failedToStart(String)
        /// Asking iCloud whether the parent is signed in.
        case checking
        /// No iCloud account on this device, or iCloud is turned off for Newbee.
        case signedOut
        /// iCloud is restricted (Screen Time, a managed device).
        case restricted
        /// iCloud can't be reached right now.
        case temporarilyUnavailable
        case syncing
        /// The last import or export failed; CloudKit retries on its own.
        case failed(String)
        /// Everything that was asked for has synced.
        case upToDate(Date?)
    }

    /// The iCloud container, or `nil` when this store doesn't sync.
    let containerID: String?
    private(set) var status: Status
    /// Goes up by one each time changes from iCloud finish arriving. The app observes it to
    /// refresh what isn't driven by `@Query`: the timer, Live Activity, reminders and photo.
    private(set) var importCount = 0
    /// Runs after each import, also when iOS woke the app in the background for it.
    @ObservationIgnored var onImport: (@MainActor () -> Void)?

    @ObservationIgnored private var accountStatus: CKAccountStatus?
    @ObservationIgnored private var inFlight = Set<UUID>()
    @ObservationIgnored private var lastError: String?
    @ObservationIgnored private var lastSuccess: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(containerID: String?, startError: Error? = nil) {
        self.containerID = containerID
        if let startError {
            status = .failedToStart(startError.localizedDescription)
        } else {
            status = containerID == nil ? .unavailable : .checking
        }
    }

    /// Starts listening. Call once, after the store is open.
    func start() {
        guard let containerID, observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let change = CloudSyncEvent(event)
            // The monitor lives as long as the app (`AppDependencies.shared`).
            Task { @MainActor in self.handle(change) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
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
        updateStatus()
    }

    func handle(_ change: CloudSyncEvent) {
        if !change.finished {
            inFlight.insert(change.id)
        } else {
            inFlight.remove(change.id)
            if change.succeeded {
                lastError = nil
                lastSuccess = change.endDate ?? .now
                if change.kind == .import {
                    importCount += 1
                    onImport?()
                }
            } else {
                lastError = change.errorMessage ?? String(localized: "Something went wrong.")
            }
        }
        updateStatus()
    }

    private func updateStatus() {
        guard containerID != nil else { return }
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
        } else if let lastError {
            status = .failed(lastError)
        } else if accountStatus == nil && lastSuccess == nil {
            status = .checking
        } else {
            status = .upToDate(lastSuccess)
        }
    }
}

/// The parts of an event the monitor needs, copied off the notification.
struct CloudSyncEvent: Sendable {
    enum Kind: Sendable { case setup, `import`, export }
    let id: UUID
    let kind: Kind
    let finished: Bool
    let succeeded: Bool
    let endDate: Date?
    let errorMessage: String?

    init(id: UUID, kind: Kind, finished: Bool, succeeded: Bool, endDate: Date?, errorMessage: String?) {
        self.id = id
        self.kind = kind
        self.finished = finished
        self.succeeded = succeeded
        self.endDate = endDate
        self.errorMessage = errorMessage
    }

    init(_ event: NSPersistentCloudKitContainer.Event) {
        let kind: Kind = switch event.type {
        case .import: .import
        case .export: .export
        default: .setup
        }
        self.init(
            id: event.identifier,
            kind: kind,
            finished: event.endDate != nil,
            succeeded: event.succeeded,
            endDate: event.endDate,
            errorMessage: event.error.map(Self.message(for:))
        )
    }

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
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
