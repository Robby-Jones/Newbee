import NewbeeKit
import NewbeeShared
import SwiftUI

/// Settings → On-Call Shift (docs/NIGHT_SHIFT.md): whether the reminder rings as an alarm. Shown
/// once a partner is on the log, on iPhones that can ring alarms. A shift itself starts from Home,
/// where its end time is picked.
struct NightShiftSettingsSection: View {
    @Bindable var preferences: AppPreferences
    @Environment(NightShiftModel.self) private var model: NightShiftModel?
    @State private var alarmsDenied = false

    var body: some View {
        if let model, model.hasPartner, model.supportsAlarm {
            Section {
                Toggle("Ring as alarm", isOn: Binding(
                    get: { preferences.nightShiftAlarm },
                    set: { isOn in
                        Task { alarmsDenied = await !model.setAlarm(isOn) }
                    }
                ))
                .accessibilityIdentifier("settings.nightShiftAlarm")
            } header: {
                SettingsSectionHeader(
                    "On-Call Shift",
                    info: Self.info,
                    identifier: "nightShift"
                )
            } footer: {
                VStack(alignment: .leading, spacing: NBSpacing.xs) {
                    if !model.remindersAreOn {
                        Text("Feed reminders are off, so nothing rings.")
                    }
                    if alarmsDenied {
                        Text("Alarms are off for Newbee. Turn them on in iOS Settings.")
                            .foregroundStyle(NBColor.destructive)
                    }
                }
            }
        }
    }

    static var info: String {
        String(localized: "Tap \u{201C}Start on-call\u{201D} on Home and pick when your shift ends. Until then, feed reminders ring only on your iPhone, and your partner gets a summary. An alarm rings even in Silent mode.")
    }
}
