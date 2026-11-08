import ActivityKit
import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI
import UIKit

/// Settings (docs/UX_SPEC.md §3.10): baby profile, units and bottle presets, reminders,
/// Live Activities, appearance, data (export, backup, delete all) and about.
///
/// The Settings tab.
struct SettingsView: View {
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    @Environment(ReminderScheduler.self) private var reminders: ReminderScheduler?

    var body: some View {
        Form {
            BabyProfileSection()
            if let preferences {
                UnitsSection(preferences: preferences)
                RemindersSection(preferences: preferences, reminders: reminders)
                LiveActivitiesSection()
                AppearanceSection(preferences: preferences)
            }
            DataSection()
            AboutSection()
        }
        .navigationTitle("Settings")
        .task { await reminders?.reschedule() }
    }
}

// MARK: - Baby

/// Single-baby MVP: edits the first `Baby`, creating it on the first edit.
private struct BabyProfileSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Baby.createdAt) private var babies: [Baby]

    var body: some View {
        let baby = babies.first
        Section {
            TextField("Name or nickname", text: Binding(
                get: { baby?.name ?? "" },
                set: { name in edit { $0.name = name } }
            ))
            .textContentType(.givenName)
            .submitLabel(.done)
            .accessibilityIdentifier("settings.babyName")

            Toggle("Birth date", isOn: Binding(
                get: { baby?.birthDate != nil },
                set: { on in edit { $0.birthDate = on ? Calendar.current.startOfDay(for: .now) : nil } }
            ))
            if let birthDate = baby?.birthDate {
                DatePicker(
                    "Born",
                    selection: Binding(get: { birthDate }, set: { date in edit { $0.birthDate = date } }),
                    in: ...Date.now,
                    displayedComponents: .date
                )
            }
        } header: {
            Text("Baby")
        } footer: {
            if let birthDate = baby?.birthDate {
                Text(BabyAge.text(from: birthDate))
            } else {
                Text("Optional. Shown on Home and only stored on this iPhone.")
            }
        }
    }

    private func edit(_ change: (Baby) -> Void) {
        let baby: Baby
        if let existing = babies.first {
            baby = existing
        } else {
            baby = Baby()
            context.insert(baby)
        }
        change(baby)
        try? context.save()
    }
}

/// "3 wk 2 d old", "4 mo 1 wk old". Shown in Settings and on Home.
enum BabyAge {
    static func text(from birth: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .weekOfMonth, .day], from: calendar.startOfDay(for: birth), to: calendar.startOfDay(for: now))
        let months = parts.month ?? 0
        let weeks = parts.weekOfMonth ?? 0
        let days = parts.day ?? 0
        if months > 0 {
            return String(localized: "\(months) mo \(weeks) wk old")
        }
        if weeks > 0 {
            return days > 0 ? String(localized: "\(weeks) wk \(days) d old") : String(localized: "\(weeks) wk old")
        }
        return days == 1 ? String(localized: "1 day old") : String(localized: "\(days) days old")
    }
}

// MARK: - Units and presets

private struct UnitsSection: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        let unit = preferences.volumeUnit
        let presets = BottlePresets.amounts(storedML: preferences.bottlePresetsML, unit: unit)
        Section {
            Picker("Bottle unit", selection: $preferences.volumeUnit) {
                Text("mL").tag(VolumeUnit.milliliters)
                Text("oz").tag(VolumeUnit.fluidOunces)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.unit")

            ForEach(Array(presets.enumerated()), id: \.offset) { index, amount in
                Stepper(
                    onIncrement: { update(presets, index: index, to: amount.stepped(by: 1)) },
                    onDecrement: { update(presets, index: index, to: amount.stepped(by: -1)) }
                ) {
                    HStack {
                        Text("Preset \(index + 1)")
                        Spacer()
                        Text(amount.formatted)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if preferences.bottlePresetsML != nil {
                Button("Reset presets") { preferences.bottlePresetsML = nil }
            }
        } header: {
            Text("Units")
        } footer: {
            Text("Quick amounts on the Log Bottle sheet.")
        }
    }

    private func update(_ presets: [BottleAmount], index: Int, to amount: BottleAmount) {
        guard amount.value > 0 else { return }
        var values = presets
        values[index] = amount
        preferences.bottlePresetsML = values.map(\.milliliters)
    }
}

// MARK: - Reminders

private struct RemindersSection: View {
    @Bindable var preferences: AppPreferences
    let reminders: ReminderScheduler?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let settings = preferences.reminders
        Section {
            if reminders?.permission == .notDetermined, settings.needsNotifications {
                Button {
                    Task { await reminders?.requestPermission() }
                } label: {
                    Label("Allow notifications for reminders", systemImage: "bell.badge")
                }
                .accessibilityIdentifier("settings.allowNotifications")
            }
            if reminders?.permission == .denied, settings.needsNotifications {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    Label("Notifications are off for Newbee. Turn them on in iOS Settings.", systemImage: "bell.slash")
                        .foregroundStyle(NBColor.destructive)
                }
            }

            Toggle("Feeding reminder", isOn: $preferences.reminders.isEnabled)
                .accessibilityIdentifier("settings.reminderToggle")
            if settings.isEnabled {
                Picker("Remind after", selection: $preferences.reminders.interval) {
                    ForEach(ReminderSettings.intervalChoices, id: \.self) { interval in
                        Text(DurationText.short(interval)).tag(interval)
                    }
                }
                Picker("Count from", selection: $preferences.reminders.basis) {
                    Text("Start of last feed").tag(ReminderSettings.Basis.start)
                    Text("End of last feed").tag(ReminderSettings.Basis.end)
                }
                Toggle("Quiet hours", isOn: Binding(
                    get: { preferences.reminders.quietHours != nil },
                    set: { preferences.reminders.quietHours = $0 ? .overnight : nil }
                ))
                if let quiet = settings.quietHours {
                    DatePicker("From", selection: minuteBinding(quiet.startMinute) {
                        preferences.reminders.quietHours = QuietHours(startMinute: $0, endMinute: quiet.endMinute)
                    }, displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minuteBinding(quiet.endMinute) {
                        preferences.reminders.quietHours = QuietHours(startMinute: quiet.startMinute, endMinute: $0)
                    }, displayedComponents: .hourAndMinute)
                }
            }

            Toggle("\u{201C}Still feeding?\u{201D} check", isOn: $preferences.reminders.stillFeedingEnabled)
            if settings.stillFeedingEnabled {
                Picker("Ask after", selection: $preferences.reminders.stillFeedingThreshold) {
                    ForEach(ReminderSettings.stillFeedingChoices, id: \.self) { interval in
                        Text(DurationText.short(interval)).tag(interval)
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                if let next = nextReminderText { Text(next) }
                Text("A gentle nudge, not medical advice. Quiet hours hold feeding reminders until morning; \u{201C}Still feeding?\u{201D} asks when one side or a pause runs long, in case the timer was left on.")
            }
        }
        .onChange(of: preferences.reminders) { old, new in
            Task {
                // Ask the first time something that notifies is switched on.
                if new.needsNotifications, !old.needsNotifications || reminders?.permission == .notDetermined {
                    await reminders?.requestPermission()
                } else {
                    await reminders?.reschedule()
                }
            }
        }
    }

    private var nextReminderText: String? {
        guard let next = reminders?.pending.min(by: { $0.fireDate < $1.fireDate }) else { return nil }
        let time = next.fireDate.formatted(date: Calendar.current.isDateInToday(next.fireDate) ? .omitted : .abbreviated, time: .shortened)
        return switch next.kind {
        case .feedDue: String(localized: "Next feeding reminder: \(time).")
        case .stillFeeding: String(localized: "\u{201C}Still feeding?\u{201D} check at \(time).")
        }
    }

    /// A time-of-day picker over minutes after midnight.
    private func minuteBinding(_ minute: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        )
    }
}

// MARK: - Live Activities

private struct LiveActivitiesSection: View {
    @Environment(\.openURL) private var openURL
    @State private var enabled = ActivityAuthorizationInfo().areActivitiesEnabled

    var body: some View {
        Section {
            LabeledContent("Lock Screen timer", value: enabled ? String(localized: "On") : String(localized: "Off"))
            if !enabled {
                Button("Turn on in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Live Activities")
        } footer: {
            Text("While a breastfeed runs, the timer and side buttons stay on the Lock Screen and in the Dynamic Island. After you end a feed, it counts the time since the last feed, with buttons to start the next one.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        }
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $preferences.appearance) {
                ForEach(AppPreferences.Appearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
        }
    }
}

// MARK: - Data

private struct DataSection: View {
    @Environment(\.dataManagement) private var actions
    @Environment(FeedingSessionUIModel.self) private var sessionModel: FeedingSessionUIModel?
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?
    @State private var sharing: SharedFile?
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button {
                export()
            } label: {
                Label("Export feeds (CSV)", systemImage: "square.and.arrow.up")
            }
            .disabled(actions == nil)
            .accessibilityIdentifier("settings.export")

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete all data", systemImage: "trash")
                    .foregroundStyle(NBColor.destructive)
            }
            .disabled(actions == nil)
            .accessibilityIdentifier("settings.deleteAll")
        } header: {
            Text("Your data")
        } footer: {
            Text("Feeds are stored only on this iPhone and are included in its iCloud or computer backup. Export a CSV to share with your pediatrician or keep a copy.")
        }
        .sheet(item: $sharing) { file in
            ShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $confirmingDelete) {
            DeleteAllDataSheet { try await deleteAll() }
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func export() {
        guard let actions else { return }
        do {
            sharing = SharedFile(url: try actions.exportCSV())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAll() async throws {
        guard let actions else { return }
        try await actions.deleteAll()
        // Undo toasts refer to feeds that no longer exist.
        sessionModel?.toast = nil
        bottleModel?.toast = nil
        bottleModel?.refresh()
        pumpModel?.toast = nil
        pumpModel?.refresh()
    }
}

/// Typed confirmation for the one action that can't be undone.
struct DeleteAllDataSheet: View {
    let delete: @MainActor () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    static let confirmationWord = "DELETE"

    private var confirmed: Bool {
        typed.trimmingCharacters(in: .whitespaces).uppercased() == Self.confirmationWord
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes every feed, the baby profile and your settings on this iPhone. It can't be undone.")
                    TextField("Type \(Self.confirmationWord) to confirm", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .accessibilityIdentifier("deleteAll.confirmField")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(NBColor.destructive)
                    } else {
                        Text("Export a CSV first if you want a copy.")
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await run() }
                    } label: {
                        HStack {
                            Text("Delete everything")
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!confirmed || isDeleting)
                    .accessibilityIdentifier("deleteAll.confirm")
                }
            }
            .navigationTitle("Delete all data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private func run() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await delete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    var body: some View {
        Section {
            LabeledContent("Version", value: Self.version)
            Label("Newbee collects no data. Nothing leaves your iPhone unless you export it.", systemImage: "lock.shield")
                .font(.footnote)
            Label("Newbee is a log, not medical advice. Ask your pediatrician about feeding concerns.", systemImage: "stethoscope")
                .font(.footnote)
        } header: {
            Text("About")
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
        .environment(AppPreferences(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}
