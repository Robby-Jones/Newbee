import CloudKit
import Foundation
import Observation
import SwiftData
import UIKit
import os

/// Sharing the feeding log with the other parent (docs/ICLOUD_SYNC.md).
///
/// One parent invites the other from Settings with Apple's own sharing sheet. The invited parent
/// taps the link, and from then on both phones sync with the same log. Either can add, change and
/// delete feeds. Settings stay separate on each phone.
@MainActor
@Observable
final class CloudSharing {
    enum Status: Equatable {
        /// This parent's own log; nobody else is on it.
        case notShared
        /// This parent invited someone who hasn't joined yet.
        case invited
        /// This parent's log, with the other parent on it.
        case shared
        /// This phone uses the other parent's log.
        case joined
    }

    /// Something to tell the parent, wherever they are in the app.
    enum Notice: Identifiable, Equatable {
        case joined
        case stopped
        case failed(String)

        var id: String {
            switch self {
            case .joined: "joined"
            case .stopped: "stopped"
            case .failed(let message): "failed-\(message)"
            }
        }
    }

    private(set) var status: Status = .notShared
    /// True while a share is being prepared or an invitation accepted.
    private(set) var isWorking = false
    var notice: Notice?

    @ObservationIgnored private let engine: CloudSyncEngine
    @ObservationIgnored private let modelContainer: ModelContainer
    @ObservationIgnored private let controllerDelegate = SharingControllerDelegate()
    @ObservationIgnored private let log = Logger(subsystem: "com.robbyjones.newbee", category: "sharing")
    /// True while this parent leaves on purpose ("Delete all data", turning sync off), when the
    /// screen they're on already said so.
    @ObservationIgnored private var isLeavingOnPurpose = false

    init(engine: CloudSyncEngine, modelContainer: ModelContainer) {
        self.engine = engine
        self.modelContainer = modelContainer
        status = engine.isJoined ? .joined : .notShared
        controllerDelegate.onChange = { [weak self] in
            Task { [weak self] in await self?.sharingSheetChangedSomething() }
        }
        controllerDelegate.onError = { [weak self] error in
            self?.notice = .failed(Self.message(for: error))
        }
    }

    // MARK: - Status

    /// The sync engine joined or left a shared log, or the share changed on the server.
    func engineChangedSharing() {
        let wasJoined = status == .joined
        if engine.isJoined {
            status = .joined
        } else if wasJoined {
            status = .notShared
            // Leaving on purpose needs no "your feeds are still here".
            if !isLeavingOnPurpose {
                notice = .stopped
            }
        }
        Task { await refresh() }
    }

    /// The invited parent chose "Delete all data": they leave the shared log first, so nothing is
    /// deleted for the other parent. Does nothing on the phone that owns the log.
    func leaveBeforeDeletingEverything() async throws {
        guard engine.isJoined else { return }
        isLeavingOnPurpose = true
        defer { isLeavingOnPurpose = false }
        try await engine.leaveSharedLog()
        status = .notShared
    }

    /// "Sync with iCloud" is being turned off, so sharing ends: the parent who shared the log
    /// stops sharing it, and the invited parent leaves. Either way the partner keeps every feed so
    /// far, and so does this phone. Throws without changing anything if iCloud can't be reached
    /// while the log is shared: the partner would keep syncing with a log nobody updates.
    func endBeforeTurningOffSync() async throws {
        guard engine.isRunning else { return }
        isLeavingOnPurpose = true
        defer { isLeavingOnPurpose = false }
        if engine.isJoined {
            try await engine.leaveSharedLog()
        } else {
            do {
                // For the owner, deleting the share removes everyone else from it. Their phones
                // see the shared log disappear, and keep their copy.
                _ = try await engine.container.privateCloudDatabase.deleteRecord(withID: shareID)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                // Never shared.
            } catch {
                // Offline, say. Nothing to stop if nothing is known to be shared.
                guard status == .notShared else { throw error }
            }
        }
        status = .notShared
    }

    /// Sync was turned off: there is no shared log any more.
    func syncDidStop() {
        status = .notShared
    }

    /// Asks iCloud who is on the log.
    func refresh() async {
        guard engine.isRunning else {
            status = .notShared
            return
        }
        do {
            let share = try await engine.activeDatabase.record(for: shareID) as? CKShare
            status = Self.status(for: share?.participants.map { Participant($0) } ?? [], joined: engine.isJoined)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            status = engine.isJoined ? .joined : .notShared
        } catch {
            // Offline or signed out: keep showing what was last known.
            log.info("Couldn't read the share: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The parts of a share participant the status depends on.
    struct Participant: Equatable {
        var isOwner: Bool
        var hasAccepted: Bool

        init(isOwner: Bool, hasAccepted: Bool) {
            self.isOwner = isOwner
            self.hasAccepted = hasAccepted
        }

        init(_ participant: CKShare.Participant) {
            isOwner = participant.role == .owner
            hasAccepted = participant.acceptanceStatus == .accepted
        }
    }

    static func status(for participants: [Participant], joined: Bool) -> Status {
        if joined { return .joined }
        let others = participants.filter { !$0.isOwner }
        if others.contains(where: \.hasAccepted) { return .shared }
        return others.isEmpty ? .notShared : .invited
    }

    private var shareID: CKRecord.ID {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: engine.activeZoneID)
    }

    // MARK: - Inviting and managing

    /// Opens Apple's sharing sheet: to invite the other parent, to see who is on the log, to stop
    /// sharing, or (for the invited parent) to leave.
    func openSharingSheet() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let share = try await currentShare()
            guard let presenter = Self.topViewController() else { return }
            let controller = UICloudSharingController(share: share, container: engine.container)
            // Only people who are invited, and they can log feeds too.
            controller.availablePermissions = [.allowPrivate, .allowReadWrite]
            controller.delegate = controllerDelegate
            controllerDelegate.title = share[CKShare.SystemFieldKey.title] as? String
            controller.popoverPresentationController?.sourceView = presenter.view
            presenter.present(controller, animated: true)
        } catch {
            log.error("Couldn't open sharing: \(error.localizedDescription, privacy: .public)")
            notice = .failed(Self.message(for: error))
        }
    }

    /// The share for the log this phone syncs with, created the first time the owner asks.
    private func currentShare() async throws -> CKShare {
        if !engine.isJoined {
            try await engine.ensureOwnZone()
        }
        let database = engine.activeDatabase
        do {
            if let share = try await database.record(for: shareID) as? CKShare {
                return share
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No share yet.
        }
        guard !engine.isJoined else { throw SharingError.shareGone }
        let share = CKShare(recordZoneID: engine.activeZoneID)
        share[CKShare.SystemFieldKey.title] = shareTitle()
        share.publicPermission = .none
        let result = try await database.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw SharingError.shareGone
        }
        return saved
    }

    /// What the invitation is called in Messages: "Ella's feeding log".
    private func shareTitle() -> String {
        let name = Baby.primary(in: modelContainer.mainContext)?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? String(localized: "Newbee feeding log") : String(localized: "\(name)'s feeding log")
    }

    private func sharingSheetChangedSomething() async {
        // The invited parent may have just left: notice that the shared zone is gone.
        try? await engine.fetchSharedChanges()
        await refresh()
    }

    // MARK: - Joining

    /// The parent tapped an invitation link. Their own feeds are merged into the shared log.
    func accept(_ metadata: CKShare.Metadata) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            // Everything in this parent's own iCloud should be on the phone before the logs merge.
            try? await engine.fetchOwnChanges()
            _ = try await engine.container.accept(metadata)
            try await engine.fetchSharedChanges()
            await refresh()
            notice = engine.isJoined ? .joined : nil
        } catch {
            log.error("Couldn't accept the invitation: \(error.localizedDescription, privacy: .public)")
            notice = .failed(Self.message(for: error))
        }
    }

    // MARK: - Helpers

    enum SharingError: LocalizedError {
        case shareGone

        var errorDescription: String? {
            String(localized: "This shared log isn't available any more.")
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure:
                return String(localized: "No internet connection. Try again when you're back online.")
            case .notAuthenticated:
                return String(localized: "Sign in to iCloud in the Settings app first.")
            case .quotaExceeded:
                return String(localized: "Your iCloud storage is full.")
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// `UICloudSharingController` reports back through an Objective-C delegate.
@MainActor
private final class SharingControllerDelegate: NSObject, UICloudSharingControllerDelegate {
    var title: String?
    var onChange: (@MainActor () -> Void)?
    var onError: (@MainActor (Error) -> Void)?

    func itemTitle(for csc: UICloudSharingController) -> String? {
        title
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        onError?(error)
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        onChange?()
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        onChange?()
    }
}
