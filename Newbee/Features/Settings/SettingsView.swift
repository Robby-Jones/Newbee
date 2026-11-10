import ActivityKit
import NewbeeKit
import NewbeeShared
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Settings (docs/UX_SPEC.md §3.10): baby profile, units and bottle presets, reminders,
/// Live Activities, appearance, data (export, import, backup, delete all) and about.
///
/// The Settings tab.
struct SettingsView: View {
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    @Environment(ReminderScheduler.self) private var reminders: ReminderScheduler?
    @State private var dataPresentation: DataPresentation?
    @State private var dataError: String?
    @State private var isConfirmingRemoveImported = false
    @Query(FeedingSession.imported()) private var importedSessions: [FeedingSession]
    @Environment(\.dataManagement) private var actions
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?

    var body: some View {
        Form {
            BabyProfileSection()
            if let preferences {
                UnitsSection(preferences: preferences)
                TimeSinceLastFeedSection(preferences: preferences)
                RemindersSection(preferences: preferences, reminders: reminders)
                LiveActivitiesSection()
                AppearanceSection(preferences: preferences)
            }
            ICloudSyncSection()
            DataSection(
                presentation: $dataPresentation,
                errorMessage: $dataError,
                importedCount: importedSessions.count,
                isConfirmingRemoveImported: $isConfirmingRemoveImported
            )
            AboutSection()
        }
        // Presented from the Form, not from the Section: a modifier on a Section applies to each
        // of its rows, so every row tried to present the same sheet and it closed itself again.
        .sheet(item: $dataPresentation) { presentation in
            DataPresentationView(presentation: presentation)
        }
        .alert(
            ImportText.removeTitle(importedSessions.count),
            isPresented: $isConfirmingRemoveImported
        ) {
            Button("Remove", role: .destructive) {
                Task { await removeImported() }
            }
            .accessibilityIdentifier("removeImported.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Feeds and pumping sessions imported from Huckleberry are deleted. Everything you logged in Newbee stays.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { dataError != nil }, set: { if !$0 { dataError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dataError ?? "")
        }
        .navigationTitle("Settings")
        .task { await reminders?.reschedule() }
    }

    private func removeImported() async {
        guard let actions else { return }
        do {
            _ = try await actions.removeImported()
            // Undo toasts may refer to entries that no longer exist.
            bottleModel?.toast = nil
            bottleModel?.refresh()
            pumpModel?.toast = nil
            pumpModel?.refresh()
        } catch {
            dataError = error.localizedDescription
        }
    }
}

// MARK: - Baby

/// Single-baby MVP: edits the first `Baby`, creating it on the first edit.
private struct BabyProfileSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Baby.createdAt) private var babies: [Baby]
    @Environment(BabyPhotoStore.self) private var photo: BabyPhotoStore?

    var body: some View {
        let baby = babies.first
        Section {
            if let photo {
                BabyPhotoRow(store: photo)
            }
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
                Text("Optional. Shown on Home.")
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

/// Choose, change or remove the baby's photo, shown at the top of Home.
private struct BabyPhotoRow: View {
    let store: BabyPhotoStore

    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: NBSpacing.m) {
            BabyAvatar(image: store.image, size: 56)
            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                PhotosPicker(selection: $selection, matching: .images) {
                    Text(store.image == nil ? "Add photo" : "Change photo")
                }
                .accessibilityIdentifier("settings.babyPhoto")
                if store.image != nil {
                    Button("Remove photo", role: .destructive) { store.remove() }
                        .font(.subheadline)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(NBColor.destructive)
                }
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
            if isLoading {
                ProgressView()
            }
        }
        .padding(.vertical, NBSpacing.xs)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            selection = nil
        }
        do {
            try await store.save(item)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? BabyPhotoStore.PhotoError.unreadable.errorDescription
        }
    }
}

extension BabyPhotoStore {
    /// Saves a photo picked with `PhotosPicker`. Used by Settings and onboarding.
    func save(_ item: PhotosPickerItem) async throws {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw PhotoError.unreadable
        }
        try save(data)
    }
}

/// The baby's photo in a circle, or a heart when there's none. Used in Settings, onboarding and on Home.
struct BabyAvatar: View {
    let image: UIImage?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "heart.fill")
                    .font(size >= 80 ? .largeTitle : .title2)
                    .foregroundStyle(NBColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NBColor.accent.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
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

/// Bottle and pumping each have a unit and their own presets. The unit is a display setting:
/// every amount in the app, past entries included, is shown in it (amounts are stored in mL).
/// Presets fold away in a dropdown so the section stays short.
private struct UnitsSection: View {
    @Bindable var preferences: AppPreferences
    @State private var showsBottlePresets = false
    @State private var showsPumpPresets = false

    var body: some View {
        Section {
            UnitRow(title: "Bottle", unit: $preferences.volumeUnit, identifier: "settings.unit")
            DisclosureGroup(isExpanded: $showsBottlePresets) {
                PresetRows(
                    storedML: $preferences.bottlePresetsML,
                    presets: BottlePresets.editable(storedML: preferences.bottlePresetsML, unit: preferences.volumeUnit),
                    next: { BottlePresets.nextAmount(after: $0, unit: preferences.volumeUnit) },
                    identifier: "settings.preset"
                )
            } label: {
                PresetsLabel(
                    title: "Bottle presets",
                    presets: BottlePresets.amounts(storedML: preferences.bottlePresetsML, unit: preferences.volumeUnit)
                )
            }
            .accessibilityIdentifier("settings.bottlePresets")

            UnitRow(title: "Pumping", unit: $preferences.pumpVolumeUnit, identifier: "settings.pumpUnit")
            DisclosureGroup(isExpanded: $showsPumpPresets) {
                PresetRows(
                    storedML: $preferences.pumpPresetsML,
                    presets: PumpPresets.editable(storedML: preferences.pumpPresetsML, unit: preferences.pumpVolumeUnit),
                    next: { PumpPresets.nextAmount(after: $0, unit: preferences.pumpVolumeUnit) },
                    identifier: "settings.pumpPreset"
                )
            } label: {
                PresetsLabel(
                    title: "Pumping presets",
                    presets: PumpPresets.amounts(storedML: preferences.pumpPresetsML, unit: preferences.pumpVolumeUnit)
                )
            }
            .accessibilityIdentifier("settings.pumpPresets")
        } header: {
            Text("Bottle and pumping")
        } footer: {
            Text("Every amount in Newbee, past entries included, is shown in these units. Presets are quick amounts on the Log Bottle sheet and, for each side, on the Log Pumping sheet. Up to \(BottlePresets.maximumCount) each.")
        }
    }
}

/// "Bottle      [ mL | oz ]".
private struct UnitRow: View {
    let title: LocalizedStringKey
    @Binding var unit: VolumeUnit
    let identifier: String

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $unit) {
                Text("mL").tag(VolumeUnit.milliliters)
                Text("oz").tag(VolumeUnit.fluidOunces)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 140)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// "Bottle presets         2, 3, 4 oz": the dropdown's title with the current presets.
private struct PresetsLabel: View {
    let title: LocalizedStringKey
    let presets: [BottleAmount]

    var body: some View {
        LabeledContent(title) {
            Text(Self.summary(presets))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    /// "60, 90, 120 mL".
    static func summary(_ presets: [BottleAmount]) -> String {
        guard let unit = presets.first?.unit else { return "" }
        return "\(presets.map(\.formattedValue).joined(separator: ", ")) \(unit.symbol)"
    }
}

/// The editable presets inside a dropdown: a stepper per preset, remove (down to 1), add (up to
/// 5) and reset. Edits keep the stored order (see `BottlePresets.editable`).
private struct PresetRows: View {
    @Binding var storedML: [Double]?
    let presets: [BottleAmount]
    let next: ([BottleAmount]) -> BottleAmount
    /// "settings.preset" gives "settings.preset.1", "settings.preset.add"…
    let identifier: String

    var body: some View {
        ForEach(Array(presets.enumerated()), id: \.offset) { index, amount in
            HStack(spacing: 12) {
                if presets.count > BottlePresets.minimumCount {
                    Button {
                        remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(NBColor.destructive)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove preset \(index + 1)")
                    .accessibilityIdentifier("\(identifier).\(index + 1).remove")
                }
                Stepper(
                    onIncrement: { update(index: index, to: amount.stepped(by: 1)) },
                    onDecrement: { update(index: index, to: amount.stepped(by: -1)) }
                ) {
                    HStack {
                        Text("Preset \(index + 1)")
                        Spacer()
                        Text(amount.formatted)
                            .monospacedDigit()
                            .foregroundStyle(NBColor.secondaryText)
                    }
                }
            }
            .accessibilityIdentifier("\(identifier).\(index + 1)")
        }
        if presets.count < BottlePresets.maximumCount {
            Button {
                add()
            } label: {
                Label("Add preset", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("\(identifier).add")
        }
        if storedML != nil {
            Button("Reset presets") { storedML = nil }
                .accessibilityIdentifier("\(identifier).reset")
        }
    }

    private func update(index: Int, to amount: BottleAmount) {
        guard amount.value > 0 else { return }
        var values = presets
        values[index] = amount
        storedML = values.map(\.milliliters)
    }

    private func add() {
        guard presets.count < BottlePresets.maximumCount else { return }
        let values = presets + [next(presets)]
        withAnimation { storedML = values.map(\.milliliters) }
    }

    private func remove(at index: Int) {
        guard presets.count > BottlePresets.minimumCount, presets.indices.contains(index) else { return }
        var values = presets
        values.remove(at: index)
        withAnimation { storedML = values.map(\.milliliters) }
    }
}

// MARK: - Time since last feed

/// "Count from": one setting for everything that counts the time since the last feed (Home, the
/// Live Activity and feeding reminders). Stored with the reminder settings (`reminder.basis`).
private struct TimeSinceLastFeedSection: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Section {
            Picker("Count from", selection: $preferences.reminders.basis) {
                Text("Start of last feed").tag(ReminderSettings.Basis.start)
                Text("End of last feed").tag(ReminderSettings.Basis.end)
            }
            .accessibilityIdentifier("settings.countFrom")
        } header: {
            Text("Time since last feed")
        } footer: {
            Text("Used on Home, on the Lock Screen and in the Dynamic Island, and for feeding reminders.")
        }
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
    @Environment(FeedingSessionUIModel.self) private var sessionModel: FeedingSessionUIModel?
    @State private var enabled = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var refreshing = false
    @State private var refreshed = false

    var body: some View {
        Section {
            LabeledContent("Lock Screen timer", value: enabled ? String(localized: "On") : String(localized: "Off"))
            if !enabled {
                Button("Turn on in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if let sessionModel {
                Button {
                    refreshing = true
                    Task {
                        await sessionModel.refreshLiveActivity()
                        refreshing = false
                        refreshed = true
                    }
                } label: {
                    HStack {
                        Text("Refresh Live Activity")
                        Spacer()
                        if refreshing {
                            ProgressView()
                        } else if refreshed {
                            Image(systemName: "checkmark")
                                .foregroundStyle(NBColor.accent)
                                .accessibilityLabel("Refreshed")
                        }
                    }
                }
                .disabled(refreshing)
                .accessibilityIdentifier("settings.refreshLiveActivity")
            }
        } header: {
            Text("Live Activities")
        } footer: {
            Text("While a breastfeed runs, the timer and side buttons stay on the Lock Screen and in the Dynamic Island. After you end a feed, it counts the time since the last feed, with a + to open Newbee for the next one. If it's gone or looks wrong, Refresh Live Activity puts it back.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        }
    }
}

// MARK: - iCloud sync

/// Whether feeds are syncing with the parent's iCloud, and why not when they aren't.
private struct ICloudSyncSection: View {
    @Environment(CloudSyncMonitor.self) private var monitor: CloudSyncMonitor?

    var body: some View {
        if let monitor, monitor.status != .unavailable {
            Section {
                LabeledContent("iCloud sync") {
                    HStack(spacing: 6) {
                        if monitor.status == .syncing || monitor.status == .checking {
                            ProgressView()
                        }
                        Text(Self.value(for: monitor.status))
                    }
                }
                .accessibilityIdentifier("settings.iCloudSync")
                if case .upToDate(let date?) = monitor.status {
                    LabeledContent("Last synced") {
                        Text(date, format: .relative(presentation: .named))
                    }
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text(Self.footer(for: monitor.status))
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Picks up signing in to iCloud in iOS Settings.
                Task { await monitor.refreshAccountStatus() }
            }
        }
    }

    static func value(for status: CloudSyncMonitor.Status) -> String {
        switch status {
        case .unavailable, .failedToStart, .signedOut, .restricted: String(localized: "Off")
        case .checking: String(localized: "Checking")
        case .temporarilyUnavailable: String(localized: "Paused")
        case .syncing: String(localized: "Syncing")
        case .failed: String(localized: "Not synced")
        case .upToDate: String(localized: "Up to date")
        }
    }

    static func footer(for status: CloudSyncMonitor.Status) -> String {
        let about = String(localized: "Feeds, the baby profile and settings sync through your private iCloud to every iPhone and iPad signed in to your Apple ID. Only you can see them.")
        switch status {
        case .unavailable, .checking, .syncing, .upToDate:
            return about
        case .signedOut:
            return String(localized: "Sign in to iCloud in the Settings app, and check that iCloud is on for Newbee, to sync your feeds to your other devices. Until then they're kept on this iPhone.")
        case .restricted:
            return String(localized: "iCloud is restricted on this iPhone, so feeds are kept on this iPhone only.")
        case .temporarilyUnavailable:
            return String(localized: "iCloud can't be reached right now. Feeds are safe on this iPhone and sync when iCloud is back.")
        case .failed(let message):
            return String(localized: "The last sync didn't finish: \(message) Your feeds are safe on this iPhone, and Newbee keeps trying.")
        case .failedToStart(let message):
            return String(localized: "iCloud sync couldn't start: \(message) Your feeds are safe on this iPhone. Newbee tries again the next time it opens.")
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

/// What the "Your data" section has open. Settings presents it from the Form (see `SettingsView`).
enum DataPresentation: Identifiable {
    case share(SharedFile)
    case report
    case importHuckleberry
    case deleteAll

    var id: String {
        switch self {
        case .share(let file): "share-\(file.url.absoluteString)"
        case .report: "report"
        case .importHuckleberry: "importHuckleberry"
        case .deleteAll: "deleteAll"
        }
    }
}

private struct DataSection: View {
    @Binding var presentation: DataPresentation?
    @Binding var errorMessage: String?
    let importedCount: Int
    @Binding var isConfirmingRemoveImported: Bool
    @Environment(\.dataManagement) private var actions

    var body: some View {
        Section {
            Button {
                export()
            } label: {
                Label("Export feeds (CSV)", systemImage: "square.and.arrow.up")
            }
            .disabled(actions == nil)
            .accessibilityIdentifier("settings.export")

            Button {
                presentation = .report
            } label: {
                Label("Export feeding report (PDF)", systemImage: "doc.richtext")
            }
            .disabled(actions == nil)
            .accessibilityIdentifier("settings.exportPDF")

            Button {
                presentation = .importHuckleberry
            } label: {
                Label("Import from Huckleberry", systemImage: "square.and.arrow.down")
            }
            .disabled(actions == nil)
            .accessibilityIdentifier("settings.importHuckleberry")

            if importedCount > 0 {
                Button(role: .destructive) {
                    isConfirmingRemoveImported = true
                } label: {
                    Label("Remove imported data", systemImage: "arrow.uturn.backward")
                        .foregroundStyle(NBColor.destructive)
                }
                .disabled(actions == nil)
                .accessibilityIdentifier("settings.removeImported")
            }

            Button(role: .destructive) {
                presentation = .deleteAll
            } label: {
                Label("Delete all data", systemImage: "trash")
                    .foregroundStyle(NBColor.destructive)
            }
            .disabled(actions == nil)
            .accessibilityIdentifier("settings.deleteAll")
        } header: {
            Text("Your data")
        } footer: {
            Text("Feeds are stored on this iPhone and, with iCloud sync on, in your private iCloud. Share a PDF report with your pediatrician, export a CSV to keep a copy, or bring in your history from Huckleberry.")
        }
    }

    private func export() {
        guard let actions else { return }
        do {
            presentation = .share(SharedFile(url: try actions.exportCSV()))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The sheet for a `DataPresentation`: the share sheet, the PDF report options or delete all.
private struct DataPresentationView: View {
    let presentation: DataPresentation
    @Environment(\.dataManagement) private var actions
    @Environment(FeedingSessionUIModel.self) private var sessionModel: FeedingSessionUIModel?
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?

    var body: some View {
        switch presentation {
        case .share(let file):
            ShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
        case .report:
            if let actions {
                ExportReportSheet(export: actions.exportPDF)
            }
        case .importHuckleberry:
            if let actions {
                HuckleberryImportSheet(prepare: actions.prepareHuckleberryImport, commit: actions.commitImport) {
                    bottleModel?.refresh()
                    pumpModel?.refresh()
                }
            }
        case .deleteAll:
            DeleteAllDataSheet { try await deleteAll() }
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
                    Text("This permanently deletes every feed, the baby profile and your settings, on this iPhone and on your other devices that sync with the same iCloud account. It can't be undone.")
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
            Label("Newbee collects no data. Your feeds sync only through your own private iCloud, and nothing else leaves your iPhone unless you export it.", systemImage: "lock.shield")
                .font(.footnote)
            Label("Newbee is a log, not medical advice. Ask your pediatrician about feeding concerns.", systemImage: "stethoscope")
                .font(.footnote)
            Link(destination: Self.privacyPolicyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: Self.supportURL) {
                Label("Help & Support", systemImage: "questionmark.circle")
            }
        } header: {
            Text("About")
        }
    }

    /// Published from `site/` by the Website workflow (also the App Store listing's URLs).
    static let privacyPolicyURL = URL(string: "https://robby-jones.github.io/Newbee/privacy.html")!
    static let supportURL = URL(string: "https://robby-jones.github.io/Newbee/support.html")!

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
