import NewbeeKit
import NewbeeShared
import SwiftUI

/// Settings → On-Call Shift (docs/NIGHT_SHIFT.md): when Home offers a shift, when it ends, and whether the reminder
/// rings as an alarm. Shown once a partner is on the log; a shift itself starts from Home.
struct NightShiftSettingsSection: View {
    @Bindable var preferences: AppPreferences
    @Environment(NightShiftModel.self) private var model: NightShiftModel?
    @State private var alarmsDenied = false

    var body: some View {
        if let model, model.hasPartner {
            Section {
                DatePicker("Shift starts at", selection: evening, displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("settings.nightShiftStart")
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
                    "On-Call Shift",
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
        let about = String(localized: "From the start time, Home shows \u{201C}Start on-call\u{201D}. Tap it, and until the end time feed reminders ring only on your iPhone, and your partner gets a summary.")
        return supportsAlarm
            ? String(localized: "\(about) An alarm rings even in Silent mode.")
            : about
    }

    private var evening: Binding<Date> {
        timeOfDay(\.nightShiftEveningMinute)
    }

    private var morning: Binding<Date> {
        timeOfDay(\.nightShiftMorningMinute)
    }

    /// A time-of-day picker over minutes after midnight.
    private func timeOfDay(_ keyPath: ReferenceWritableKeyPath<AppPreferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = preferences[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
