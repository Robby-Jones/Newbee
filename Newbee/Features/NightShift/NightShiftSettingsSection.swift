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
                Text("Night Shift")
            } footer: {
                VStack(alignment: .leading, spacing: NBSpacing.xs) {
                    Text(Self.footer(supportsAlarm: model.supportsAlarm))
                    if !preferences.reminders.isEnabled {
                        Text("The feeding reminder is off, so nothing rings during your shift.")
                    }
                    if alarmsDenied {
                        Text("Alarms are off for Newbee. Turn them on in iOS Settings.")
                            .foregroundStyle(NBColor.destructive)
                    }
                }
            }
        }
    }

    static func footer(supportsAlarm: Bool) -> String {
        let about = String(localized: "In the evening, tap \u{201C}I'm on duty tonight\u{201D} on Home. The feeding reminder then rings only on your iPhone, even in quiet hours, and your partner gets a summary in the morning.")
        return supportsAlarm
            ? String(localized: "\(about) As an alarm, it also rings in Silent mode.")
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
