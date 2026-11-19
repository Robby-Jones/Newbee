import NewbeeShared
import SwiftUI

/// Settings → Sharing: one row that opens Apple's sharing sheet, to invite the other parent, see
/// who is on the log, stop sharing or leave (docs/UX_SPEC.md §3.10, docs/ICLOUD_SYNC.md).
struct SharingSection: View {
    @Environment(CloudSharing.self) private var sharing: CloudSharing?
    @Environment(CloudSyncMonitor.self) private var monitor: CloudSyncMonitor?
    @Environment(CloudSyncSwitch.self) private var syncSwitch: CloudSyncSwitch?
    @State private var isOfferingSync = false

    var body: some View {
        if let status = SharingPreview.status {
            SharingSectionContent(status: status, isWorking: false, needsSync: false) {}
        } else if let sharing, let monitor, let syncSwitch,
                  Self.canShare(monitor.status, hasAccount: monitor.hasICloudAccount) {
            SharingSectionContent(
                status: sharing.status,
                isWorking: sharing.isWorking || syncSwitch.isWorking,
                needsSync: !syncSwitch.isOn
            ) {
                if syncSwitch.isOn {
                    Task { await sharing.openSharingSheet() }
                } else {
                    isOfferingSync = true
                }
            }
            .alert("Turn on iCloud sync?", isPresented: $isOfferingSync) {
                Button("Turn On") {
                    Task {
                        await syncSwitch.turnOn()
                        await sharing.openSharingSheet()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Sharing goes through your private iCloud. Your feeds will also sync to your other devices.")
            }
        }
    }

    /// Sharing needs iCloud. Without it the iCloud section already says what to do. With sync
    /// off, the row offers to turn it on, unless this device has no iCloud to turn on.
    static func canShare(_ status: CloudSyncMonitor.Status, hasAccount: Bool = true) -> Bool {
        switch status {
        case .unavailable, .signedOut, .restricted: false
        case .off: hasAccount
        case .checking, .temporarilyUnavailable, .syncing, .failed, .upToDate: true
        }
    }
}

struct SharingSectionContent: View {
    let status: CloudSharing.Status
    let isWorking: Bool
    /// "Sync with iCloud" is off: tapping offers to turn it on first.
    let needsSync: Bool
    let open: () -> Void

    var body: some View {
        Section {
            Button(action: open) {
                HStack {
                    Label(Self.title(for: status), systemImage: "person.2")
                    Spacer()
                    if isWorking {
                        ProgressView()
                    } else if let value = Self.value(for: status) {
                        Text(value)
                            .foregroundStyle(NBColor.secondaryText)
                    }
                }
            }
            .disabled(isWorking)
            .accessibilityIdentifier("settings.sharing")
        } header: {
            SettingsSectionHeader(
                "Sharing",
                info: needsSync ? Self.needsSyncInfo : Self.info(for: status),
                identifier: "sharing"
            )
        } footer: {
            if status == .invited {
                Text(Self.invitedFooter)
            }
        }
    }

    static func title(for status: CloudSharing.Status) -> String {
        switch status {
        case .notShared: String(localized: "Share with your partner")
        case .invited, .shared, .joined: String(localized: "Partner")
        }
    }

    static func value(for status: CloudSharing.Status) -> String? {
        switch status {
        case .notShared: nil
        case .invited: String(localized: "Invited")
        case .shared, .joined: String(localized: "Sharing")
        }
    }

    static let needsSyncInfo = String(localized: "Your partner sees and logs feeds on their own iPhone. Sharing turns on iCloud sync.")

    /// Live status while an invitation is out, so it stays visible under the row.
    static let invitedFooter = String(localized: "Waiting for your partner to open the invitation. Tap to send it again or cancel it.")

    /// What sharing does, behind the header's info button.
    static func info(for status: CloudSharing.Status) -> String {
        switch status {
        case .notShared, .invited:
            String(localized: "Your partner sees and logs feeds on their own iPhone. They need Newbee and iCloud.")
        case .shared:
            String(localized: "You both see the same feeds and can add or change them. Tap to manage or stop sharing.")
        case .joined:
            String(localized: "You both see the same feeds and can add or change them. Tap to leave.")
        }
    }
}

/// Tells the parent when sharing started, ended or failed, wherever they are in the app: an
/// invitation link can open Newbee on any screen.
struct SharingNoticePresentation: ViewModifier {
    @Environment(CloudSharing.self) private var sharing: CloudSharing?

    func body(content: Content) -> some View {
        content.alert(
            Self.title(for: sharing?.notice),
            isPresented: Binding(get: { sharing?.notice != nil }, set: { if !$0 { sharing?.notice = nil } }),
            presenting: sharing?.notice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(Self.message(for: notice))
        }
    }

    static func title(for notice: CloudSharing.Notice?) -> String {
        switch notice {
        case .joined: String(localized: "You're sharing feeds")
        case .stopped: String(localized: "Sharing has ended")
        case .failed, nil: String(localized: "Sharing didn't work")
        }
    }

    static func message(for notice: CloudSharing.Notice) -> String {
        switch notice {
        case .joined:
            String(localized: "You and your partner now see the same feeds on both iPhones. The feeds you had already logged were added.")
        case .stopped:
            String(localized: "Every feed so far is still on this iPhone. From now on, your feeds are only yours.")
        case .failed(let message):
            message
        }
    }
}

extension View {
    func sharingNoticePresentation() -> some View {
        modifier(SharingNoticePresentation())
    }
}

/// UI tests and screenshots show the Sharing row without iCloud: `-sharingPreview invited`.
enum SharingPreview {
    static var status: CloudSharing.Status? {
        guard AppConfiguration.isUITesting,
              let value = UserDefaults.standard.string(forKey: "sharingPreview") else { return nil }
        switch value {
        case "notShared": return .notShared
        case "invited": return .invited
        case "shared": return .shared
        case "joined": return .joined
        default: return nil
        }
    }
}
