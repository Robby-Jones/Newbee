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

    var body: some View {
        form
            // A color theme change rebuilds the tabs (RootView), which would open this list at
            // the top again; this keeps its scroll position.
            .background(SettingsScrollKeeper())
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsPage.self) { page in
                page.destination(preferences: preferences)
            }
            .task { await reminders?.reschedule() }
    }

    private var form: some View {
        Form {
            BabyProfileSection()
            ICloudSyncRow()
            SharingSection()
            if let preferences {
                NightShiftSettingsSection(preferences: preferences)
                UnitsSection(preferences: preferences)
                BreastfeedingSection(preferences: preferences)
                TimeSinceLastFeedSection(preferences: preferences)
                Section {
                    SettingsPageRow(
                        .notifications, title: "Notifications", systemImage: "bell",
                        value: preferences.reminders.needsNotifications ? String(localized: "On") : String(localized: "Off")
                    )
                }
                LiveActivitiesSection()
                Section {
                    SettingsPageRow(.appearance, title: "Appearance", systemImage: "paintpalette", value: preferences.colorTheme.title)
                }
            }
            // Like iOS Settings: rows that open their own page.
            Section {
                SettingsPageRow(.yourData, title: "Your data", systemImage: "externaldrive")
                SettingsPageRow(.about, title: "About", systemImage: "info.circle")
            }
        }
    }
}

/// The pages Settings opens. They're pushed by value onto a path RootView keeps, so a color
/// theme change, which rebuilds the tabs, leaves the parent on the page they were on.
enum SettingsPage: Hashable {
    case iCloud, notifications, appearance, liveActivityColor, yourData, about

    @MainActor @ViewBuilder
    func destination(preferences: AppPreferences?) -> some View {
        switch self {
        case .iCloud: ICloudSettingsView()
        case .notifications: NotificationsSettingsView()
        case .appearance:
            if let preferences { AppearanceSettingsView(preferences: preferences) }
        case .liveActivityColor:
            if let preferences { LiveActivityColorView(preferences: preferences) }
        case .yourData: DataSettingsView()
        case .about: AboutSettingsView()
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .iCloud: "settings.iCloudPage"
        case .notifications: "settings.notificationsPage"
        case .appearance: "settings.appearancePage"
        case .liveActivityColor: "settings.liveActivityColor"
        case .yourData: "settings.yourData"
        case .about: "settings.about"
        }
    }
}

/// A row that opens one of Settings' pages, with the current value on the right like iOS Settings.
struct SettingsPageRow: View {
    let page: SettingsPage
    let title: LocalizedStringKey
    let systemImage: String
    let value: String?

    init(_ page: SettingsPage, title: LocalizedStringKey, systemImage: String, value: String? = nil) {
        self.page = page
        self.title = title
        self.systemImage = systemImage
        self.value = value
    }

    var body: some View {
        NavigationLink(value: page) {
            if let value {
                LabeledContent {
                    Text(value)
                } label: {
                    Label(title, systemImage: systemImage)
                }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .accessibilityIdentifier(page.accessibilityIdentifier)
    }
}

/// Keeps Settings' scroll position across the rebuild a color theme change causes.
///
/// The rebuild makes a new list, and SwiftUI's `scrollTo` didn't move a Form that was under
/// another page or sliding back in, so this saves and restores the list's own scroll view offset.
@MainActor
enum SettingsScroll {
    /// The Settings list's scroll view, found by `SettingsScrollKeeper`.
    static weak var scrollView: UIScrollView?
    /// Set as a theme is picked. Lives outside the views because the rebuild drops their state.
    static var pendingOffset: CGPoint?

    /// Called just before the theme changes. Keeps an earlier saved offset if the list hasn't
    /// been shown since (a second color picked before going back).
    static func rememberPosition() {
        if let scrollView { pendingOffset = scrollView.contentOffset }
    }

    /// Puts the saved offset on a newly shown list, once it has laid out.
    static func restore(on scrollView: UIScrollView) {
        guard pendingOffset != nil else {
            self.scrollView = scrollView
            return
        }
        DispatchQueue.main.async {
            guard let offset = pendingOffset, scrollView.window != nil else { return }
            pendingOffset = nil
            scrollView.layoutIfNeeded()
            let insets = scrollView.adjustedContentInset
            let maxY = max(scrollView.contentSize.height + insets.bottom - scrollView.bounds.height, -insets.top)
            scrollView.setContentOffset(CGPoint(x: offset.x, y: min(max(offset.y, -insets.top), maxY)), animated: false)
            self.scrollView = scrollView
        }
    }
}

/// Sits behind the Settings Form and finds its scroll view (the nearest one in the views around
/// it) whenever the list comes on screen.
private struct SettingsScrollKeeper: UIViewRepresentable {
    func makeUIView(context: Context) -> KeeperView { KeeperView() }
    func updateUIView(_ uiView: KeeperView, context: Context) {}

    final class KeeperView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = Self.firstScrollView(in: view, depth: 6) {
                    SettingsScroll.restore(on: scrollView)
                    return
                }
                ancestor = view.superview
            }
        }

        private static func firstScrollView(in view: UIView, depth: Int) -> UIScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? UIScrollView, scrollView is UICollectionView || scrollView is UITableView {
                    return scrollView
                }
            }
            guard depth > 0 else { return nil }
            for subview in view.subviews {
                if let found = firstScrollView(in: subview, depth: depth - 1) { return found }
            }
            return nil
        }
    }
}

/// Settings → iCloud: the sync switch and its status.
private struct ICloudSettingsView: View {
    var body: some View {
        Form { ICloudSyncSection() }
            .navigationTitle("iCloud")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings → Notifications: the feeding reminder, quiet hours and the "Still feeding?" check.
private struct NotificationsSettingsView: View {
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    @Environment(ReminderScheduler.self) private var reminders: ReminderScheduler?

    var body: some View {
        Form {
            if let preferences {
                RemindersSection(preferences: preferences, reminders: reminders)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reminders?.reschedule() }
    }
}

/// Settings → Appearance: mode, color, the Live Activity's colors and the app icon.
private struct AppearanceSettingsView: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Form { AppearanceSection(preferences: preferences) }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings → Your data: export, import, remove imported and delete all, on a page of its own.
struct DataSettingsView: View {
    @State private var dataPresentation: DataPresentation?
    @State private var dataError: String?
    @State private var isConfirmingRemoveImported = false
    @Query(FeedingSession.imported()) private var importedSessions: [FeedingSession]
    @Environment(\.dataManagement) private var actions
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?

    var body: some View {
        Form {
            DataSection(
                presentation: $dataPresentation,
                errorMessage: $dataError,
                importedCount: importedSessions.count,
                isConfirmingRemoveImported: $isConfirmingRemoveImported
            )
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
        .navigationTitle("Your data")
        .navigationBarTitleDisplayMode(.inline)
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

/// Settings → About: version, privacy, disclaimer and links, on a page of its own.
struct AboutSettingsView: View {
    var body: some View {
        Form {
            AboutSection()
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
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
            SettingsSectionHeader(
                "Baby",
                info: String(localized: "Optional. The name and age show under the greeting on Home."),
                identifier: "baby"
            )
        } footer: {
            if let birthDate = baby?.birthDate {
                Text(BabyAge.text(from: birthDate))
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
        // Read on the main actor here: the picker's label closure is Sendable.
        let hasPhoto = store.image != nil
        HStack(spacing: NBSpacing.m) {
            BabyAvatar(image: store.image, size: 56)
            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                PhotosPicker(selection: $selection, matching: .images) {
                    Text(hasPhoto ? "Change photo" : "Add photo")
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
            Toggle("Log pumping as total only", isOn: $preferences.pumpTotalOnly.animation())
                .accessibilityIdentifier("settings.pumpTotalOnly")
            if preferences.pumpTotalOnly {
                DisclosureGroup(isExpanded: $showsPumpPresets) {
                    PresetRows(
                        storedML: $preferences.pumpTotalPresetsML,
                        presets: PumpPresets.editableTotals(storedML: preferences.pumpTotalPresetsML, unit: preferences.pumpVolumeUnit),
                        next: { PumpPresets.nextTotalAmount(after: $0, unit: preferences.pumpVolumeUnit) },
                        maximumML: PumpRules().maximumTotalML,
                        identifier: "settings.pumpTotalPreset"
                    )
                } label: {
                    PresetsLabel(
                        title: "Pumping presets",
                        presets: PumpPresets.totalAmounts(storedML: preferences.pumpTotalPresetsML, unit: preferences.pumpVolumeUnit)
                    )
                }
                .accessibilityIdentifier("settings.pumpTotalPresets")
            } else {
                DisclosureGroup(isExpanded: $showsPumpPresets) {
                    PresetRows(
                        storedML: $preferences.pumpPresetsML,
                        presets: PumpPresets.editable(storedML: preferences.pumpPresetsML, unit: preferences.pumpVolumeUnit),
                        next: { PumpPresets.nextAmount(after: $0, unit: preferences.pumpVolumeUnit) },
                        maximumML: PumpRules().maximumPerSideML,
                        identifier: "settings.pumpPreset"
                    )
                } label: {
                    PresetsLabel(
                        title: "Pumping presets",
                        presets: PumpPresets.amounts(storedML: preferences.pumpPresetsML, unit: preferences.pumpVolumeUnit)
                    )
                }
                .accessibilityIdentifier("settings.pumpPresets")
            }
        } header: {
            SettingsSectionHeader(
                "Bottle and pumping",
                info: String(localized: "Every amount in Newbee, past entries included, is shown in these units. Presets are quick amounts on the Log Bottle sheet and, for each side, on the Log Pumping sheet. Up to \(BottlePresets.maximumCount) each. With \u{201C}Log pumping as total only\u{201D} on, Log Pumping asks for one total instead of left and right, and those sessions show as \u{201C}Total\u{201D}. Sessions you already logged keep their left and right amounts."),
                identifier: "units"
            )
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
    /// The largest preset the steppers go to.
    var maximumML: Double = BottleRules().maximumML
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
                    onIncrement: { update(index: index, to: amount.stepped(by: 1, maximumML: maximumML)) },
                    onDecrement: { update(index: index, to: amount.stepped(by: -1, maximumML: maximumML)) }
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

// MARK: - Breastfeeding

/// "Suggested starting side": which breast the Timer tags as Suggested (also Home's "Next:",
/// manual entries and the Live Activity tint). "Switch from" only shows while alternating.
private struct BreastfeedingSection: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Section {
            Picker("Suggested starting side", selection: $preferences.startingSide.mode) {
                Text("Alternate").tag(StartingSideSuggestion.Mode.alternate)
                Text("Always left").tag(StartingSideSuggestion.Mode.alwaysLeft)
                Text("Always right").tag(StartingSideSuggestion.Mode.alwaysRight)
            }
            .accessibilityIdentifier("settings.startingSide")
            if preferences.startingSide.mode == .alternate {
                Picker("Switch from", selection: $preferences.startingSide.switchFrom) {
                    Text("Side you ended on").tag(StartingSideSuggestion.SwitchFrom.ended)
                    Text("Side you started on").tag(StartingSideSuggestion.SwitchFrom.started)
                }
                .accessibilityIdentifier("settings.switchFrom")
            }
        } header: {
            SettingsSectionHeader(
                "Breastfeeding",
                info: String(
                    localized: "The side the timer suggests for the next feed. Alternate offers the other side from the one your last breastfeed ended or started on, and Left before your first feed."
                ),
                identifier: "breastfeeding"
            )
        }
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
            SettingsSectionHeader(
                "Time since last feed",
                info: String(localized: "Used on Home, on the Lock Screen and in the Dynamic Island, and for feeding reminders."),
                identifier: "timeSinceLastFeed"
            )
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
            SettingsSectionHeader(
                "Notifications",
                info: String(localized: "A gentle nudge, not medical advice. Quiet hours hold feeding reminders until morning; \u{201C}Still feeding?\u{201D} asks when one side or a pause runs long, in case the timer was left on."),
                identifier: "notifications"
            )
        } footer: {
            if let next = nextReminderText { Text(next) }
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
    @State private var refreshState = RefreshState.ready
    /// Why the last refresh didn't bring the activity back; cleared on the next tap.
    @State private var refreshProblem: String?
    @State private var refreshReset: Task<Void, Never>?

    /// The refresh button's trailing icon: a refresh symbol when it can be tapped, a spinner while
    /// it runs, then a checkmark (or a warning) for a moment before it can be tapped again.
    enum RefreshState: Equatable {
        case ready, refreshing, refreshed, failed
    }

    var body: some View {
        Section {
            LabeledContent("Lock Screen timer", value: enabled ? String(localized: "On") : String(localized: "Off"))
            if !enabled {
                Button("Turn on in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if let sessionModel {
                Button {
                    startRefresh(sessionModel)
                } label: {
                    HStack {
                        Text("Refresh Live Activity")
                        Spacer()
                        refreshIcon
                    }
                }
                .disabled(refreshState == .refreshing)
                .accessibilityIdentifier("settings.refreshLiveActivity")
                if let refreshProblem {
                    Text(refreshProblem)
                        .font(.footnote)
                        .foregroundStyle(NBColor.secondaryText)
                        .accessibilityIdentifier("settings.refreshLiveActivity.problem")
                }
            }
        } header: {
            SettingsSectionHeader(
                "Live Activities",
                info: String(localized: "While a breastfeed runs, the timer and side buttons stay on the Lock Screen and in the Dynamic Island. After you end a feed, it counts the time since the last feed, with a + to open Newbee for the next one. If it's gone or looks wrong, Refresh Live Activity puts it back."),
                identifier: "liveActivities"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        }
        .onDisappear {
            refreshReset?.cancel()
            refreshState = .ready
        }
    }

    @ViewBuilder
    private var refreshIcon: some View {
        switch refreshState {
        case .ready:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(NBColor.accent)
                .accessibilityHidden(true)
        case .refreshing:
            ProgressView()
                .accessibilityLabel("Refreshing")
        case .refreshed:
            Image(systemName: "checkmark")
                .foregroundStyle(NBColor.accent)
                .accessibilityLabel("Refreshed")
                .accessibilityIdentifier("settings.refreshLiveActivity.done")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NBColor.destructive)
                .accessibilityLabel("Couldn't refresh")
                .accessibilityIdentifier("settings.refreshLiveActivity.failed")
        }
    }

    /// How long the checkmark or warning stays before the refresh symbol comes back.
    private static let resultShownFor: Duration = .seconds(2)

    private func startRefresh(_ sessionModel: FeedingSessionUIModel) {
        refreshReset?.cancel()
        refreshProblem = nil
        refreshState = .refreshing
        Task {
            let result = await sessionModel.refreshLiveActivity()
            enabled = ActivityAuthorizationInfo().areActivitiesEnabled
            refreshProblem = Self.problem(for: result)
            withAnimation(.snappy) { refreshState = result == .shown ? .refreshed : .failed }
            refreshReset = Task {
                try? await Task.sleep(for: Self.resultShownFor)
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { refreshState = .ready }
            }
        }
    }

    /// What to tell the parent when the refresh didn't bring the activity back.
    private static func problem(for result: LiveActivityRefreshResult) -> String? {
        switch result {
        case .shown:
            nil
        case .nothingToShow:
            String(localized: "Nothing to show yet. Log a feed and it will appear.")
        case .disabled:
            String(localized: "Live Activities are turned off for Newbee in iOS Settings.")
        case .refused(let reason):
            String(localized: "iOS didn't start the Live Activity: \(reason)")
        case .removedRightAway:
            String(localized: "iOS removed the Live Activity right after it started. Try again, or restart your iPhone if it keeps happening.")
        }
    }
}

// MARK: - iCloud sync

/// The iCloud row on the Settings page; shown when iCloud sync is offered, like the section it opens.
private struct ICloudSyncRow: View {
    @Environment(CloudSyncMonitor.self) private var monitor: CloudSyncMonitor?

    var body: some View {
        if let monitor, monitor.status != .unavailable {
            Section {
                SettingsPageRow(.iCloud, title: "iCloud", systemImage: "icloud", value: ICloudSyncSection.value(for: monitor.status))
            }
        }
    }
}

/// "Sync with iCloud" (off on a fresh install), and once it's on, whether feeds are syncing and
/// why not when they aren't (docs/ICLOUD_SYNC.md).
private struct ICloudSyncSection: View {
    @Environment(CloudSyncMonitor.self) private var monitor: CloudSyncMonitor?
    @Environment(CloudSyncSwitch.self) private var syncSwitch: CloudSyncSwitch?
    @Environment(CloudSharing.self) private var sharing: CloudSharing?
    @State private var isConfirmingOff = false
    @State private var errorMessage: String?

    var body: some View {
        if let monitor, let syncSwitch, monitor.status != .unavailable {
            Section {
                Toggle(isOn: Binding(get: { syncSwitch.isOn }, set: { isOn in
                    errorMessage = nil
                    if isOn {
                        Task { await syncSwitch.turnOn() }
                    } else {
                        isConfirmingOff = true
                    }
                })) {
                    HStack(spacing: 6) {
                        Text("Sync with iCloud")
                        if syncSwitch.isWorking {
                            ProgressView()
                        }
                    }
                }
                .disabled(syncSwitch.isWorking)
                .accessibilityIdentifier("settings.iCloudSyncSwitch")
                if syncSwitch.isOn {
                    LabeledContent("Status") {
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
                }
            } header: {
                SettingsSectionHeader(
                    "iCloud",
                    info: Self.info(for: monitor.status),
                    identifier: "iCloud"
                )
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(NBColor.destructive)
                } else if let status = Self.statusFooter(for: monitor.status, hasAccount: monitor.hasICloudAccount) {
                    Text(status)
                }
            }
            .alert("Turn off iCloud sync?", isPresented: $isConfirmingOff) {
                Button("Turn Off", role: .destructive) {
                    Task {
                        do {
                            try await syncSwitch.turnOff()
                        } catch {
                            errorMessage = CloudSharing.message(for: error)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(Self.turnOffMessage(for: sharing?.status ?? .notShared))
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Picks up signing in to iCloud in iOS Settings.
                Task { await monitor.refreshAccountStatus() }
            }
        }
    }

    static func value(for status: CloudSyncMonitor.Status) -> String {
        switch status {
        case .unavailable, .off, .signedOut, .restricted: String(localized: "Off")
        case .checking: String(localized: "Checking")
        case .temporarilyUnavailable: String(localized: "Paused")
        case .syncing: String(localized: "Syncing")
        case .failed: String(localized: "Not synced")
        case .upToDate: String(localized: "Up to date")
        }
    }

    /// What sync does, behind the header's info button.
    static func info(for status: CloudSyncMonitor.Status) -> String {
        switch status {
        case .off:
            String(localized: "Feeds are kept on this iPhone only. Turn on to sync them through your private iCloud to your other devices, and to share with your partner.")
        default:
            String(localized: "Feeds, the baby profile and settings sync through your private iCloud to every iPhone and iPad signed in to your Apple ID. Only you, and a partner you share with, can see the feeds.")
        }
    }

    /// Why sync isn't working, or what to do first; nil while all is well.
    static func statusFooter(for status: CloudSyncMonitor.Status, hasAccount: Bool) -> String? {
        switch status {
        case .off:
            return hasAccount ? nil : String(localized: "First sign in to iCloud in the Settings app.")
        case .unavailable, .checking, .syncing, .upToDate:
            return nil
        case .signedOut:
            return String(localized: "Sign in to iCloud in the Settings app, and check that iCloud is on for Newbee, to sync your feeds to your other devices. Until then they're kept on this iPhone.")
        case .restricted:
            return String(localized: "iCloud is restricted on this iPhone, so feeds are kept on this iPhone only.")
        case .temporarilyUnavailable:
            return String(localized: "iCloud can't be reached right now. Feeds are safe on this iPhone and sync when iCloud is back.")
        case .failed(let message):
            return String(localized: "Some changes haven't synced yet: \(message) Your feeds are safe on this iPhone, and Newbee keeps trying.")
        }
    }

    /// What turning sync off does, by who shares the log.
    static func turnOffMessage(for status: CloudSharing.Status) -> String {
        let about = String(localized: "Your feeds stay on this iPhone and in iCloud, but changes stop syncing to your other devices.")
        return switch status {
        case .notShared:
            about
        case .invited, .shared:
            String(localized: "\(about) Sharing with your partner stops too. They keep a copy of every feed so far.")
        case .joined:
            String(localized: "\(about) You also leave your partner's log. They keep every feed, and so does this iPhone.")
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
        } header: {
            SettingsSectionHeader(
                "Export and import",
                info: String(localized: "Feeds are stored on this iPhone and, with iCloud sync on, in your private iCloud. Share a PDF report with your pediatrician, export a CSV to keep a copy, or bring in your history from Huckleberry."),
                identifier: "data"
            )
        }

        Section {
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
    @Environment(CloudSharing.self) private var sharing: CloudSharing?
    @Environment(CloudSyncSwitch.self) private var syncSwitch: CloudSyncSwitch?
    @State private var typed = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    static let confirmationWord = "DELETE"

    /// What deleting reaches depends on whether feeds sync, and who shares the log
    /// (docs/ICLOUD_SYNC.md).
    static func warning(for status: CloudSharing.Status, syncs: Bool = true) -> String {
        guard syncs else {
            return String(localized: "This permanently deletes every feed, the baby profile and your settings from this iPhone. It can't be undone.")
        }
        return switch status {
        case .notShared, .invited:
            String(localized: "This permanently deletes every feed, the baby profile and your settings, on this iPhone and on your other devices that sync with the same iCloud account. It can't be undone.")
        case .shared:
            String(localized: "This permanently deletes every feed, the baby profile and your settings, on this iPhone, on your other devices and on your partner's iPhone. It can't be undone.")
        case .joined:
            String(localized: "This deletes every feed, the baby profile and your settings from this iPhone, and stops sharing. Your partner keeps their feeds. It can't be undone.")
        }
    }

    private var confirmed: Bool {
        typed.trimmingCharacters(in: .whitespaces).uppercased() == Self.confirmationWord
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(Self.warning(
                        for: SharingPreview.status ?? sharing?.status ?? .notShared,
                        syncs: SharingPreview.status != nil || syncSwitch?.isOn == true
                    ))
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
            errorMessage = CloudSharing.message(for: error)
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    var body: some View {
        Section {
            LabeledContent("Version", value: Self.version)
            Label("Newbee collects no data. Your feeds stay on your iPhone. With iCloud sync on, they sync only through your own iCloud, to your devices and to a partner you invite. Nothing else leaves your iPhone unless you export it.", systemImage: "lock.shield")
                .font(.footnote)
            Label("Newbee is a log, not medical advice. Ask your pediatrician about feeding concerns.", systemImage: "stethoscope")
                .font(.footnote)
            Link(destination: Self.privacyPolicyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: Self.supportURL) {
                Label("Help & Support", systemImage: "questionmark.circle")
            }
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
