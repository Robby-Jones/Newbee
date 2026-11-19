import NewbeeKit
import NewbeeShared
import SwiftUI

/// Settings → Night Shift (docs/NIGHT_SHIFT.md): when a shift ends, and whether the reminder
/// rings as an alarm. Shown once a partner is on the log; a shift itself starts from Home.
struct NightShiftSettingsSection: View {
    @Bindable var preferences: AppPreferences
    @Environment(NightShiftModel.self) private var model: NightShiftModel?
    @State private var alarmsDenied = false

    var body: some View {
        if let model, model.hasPartner {
            Section {
                DatePicker("Shift ends at", selection: morning, displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("settings.nightShiftEnd")
                if model.supportsAlarm {
                    Toggle("Ring as alarm", isOn: Binding(
                        get: { preferences.nightShiftAlarm },
                        set: { isOn in
                            Task { alarmsDenied = await !model.setAlarm(isOn) }
                        }
                    ))
                    .accessibilityIdentifier("settings.nightShiftAlarm")
                }
            } header: {
                SettingsSectionHeader(
                    "Night Shift",
                    info: Self.info(supportsAlarm: model.supportsAlarm),
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

    static func info(supportsAlarm: Bool) -> String {
        let about = String(localized: "Tap \u{201C}I'm on duty tonight\u{201D} on Home. Until this time, feed reminders ring only on your iPhone, and your partner gets a summary.")
        return supportsAlarm
            ? String(localized: "\(about) An alarm rings even in Silent mode.")
            : about
    }

    /// A time-of-day picker over minutes after midnight.
    private var morning: Binding<Date> {
        Binding(
            get: {
                let minute = preferences.nightShiftMorningMinute
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences.nightShiftMorningMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
