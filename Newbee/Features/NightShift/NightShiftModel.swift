import Foundation
import NewbeeKit
import Observation
import SwiftData

/// What reminders need to know about tonight (`ReminderScheduler`).
struct NightShiftReminderContext: Sendable {
    var duty: NightDuty = .none
    /// The night so far, for the parent who is asleep: the summary notification is written from it.
    var summary: NightSummary?
    /// When "While you slept" is delivered: the shift's end, or right away for a shift that was
    /// just ended early.
    var summaryAt: Date?
    /// "Ring as alarm" is on in Settings.
    var ringsAsAlarm = false
}

/// Night Shift for the UI (docs/NIGHT_SHIFT.md): which card Home shows, and the three taps that
/// change who is on duty. The rules themselves are NewbeeKit's `NightShift` and `NightShiftCard`.
@MainActor
@Observable
final class NightShiftModel {
    let store: NightShiftStore
    /// True while iCloud is asked who this parent is.
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let sharing: CloudSharing?
    @ObservationIgnored private let engine: CloudSyncEngine?
    @ObservationIgnored private let reminders: ReminderScheduler?
    @ObservationIgnored private let alarms: any NightAlarmClient
    @ObservationIgnored private let modelContainer: ModelContainer?
    @ObservationIgnored private let clock: any AppClock

    init(
        store: NightShiftStore,
        preferences: AppPreferences,
        sharing: CloudSharing?,
        engine: CloudSyncEngine?,
        reminders: ReminderScheduler?,
        alarms: any NightAlarmClient,
        modelContainer: ModelContainer?,
        clock: any AppClock
    ) {
        self.store = store
        self.preferences = preferences
        self.sharing = sharing
        self.engine = engine
        self.reminders = reminders
        self.alarms = alarms
        self.modelContainer = modelContainer
        self.clock = clock
    }

    // MARK: - State

    /// Stands in for a partner on the log where there is no iCloud to share through (tests).
    @ObservationIgnored var hasPartnerOverride: Bool?

    /// Night Shift is about two parents: it only exists once the partner is on the log.
    var hasPartner: Bool {
        if let hasPartnerOverride { return hasPartnerOverride }
        return switch SharingPreview.status ?? sharing?.status ?? .notShared {
        case .shared, .joined: true
        case .notShared, .invited: false
        }
    }

    var schedule: NightShiftSchedule {
        NightShiftSchedule(
            eveningMinute: preferences.nightShiftEveningMinute,
            morningMinute: preferences.nightShiftMorningMinute
        )
    }

    /// The card for Home right now, if any.
    func card(at now: Date) -> NightShiftCard? {
        if let preview = NightShiftPreview.card(at: now) { return preview }
        guard hasPartner else { return nil }
        return NightShiftCard.current(
            shift: store.shift, me: store.me, now: now, schedule: schedule, dismissedShiftStart: store.dismissedSummaryStart
        )
    }

    func duty(at now: Date) -> NightDuty {
        guard hasPartner, let shift = store.shift, let me = store.me else { return .none }
        return shift.duty(for: me, at: now)
    }

    /// Whether the feed reminder is on, so the card can say what will ring.
    /// Screenshots show the usual case, with the reminder on.
    var remindersAreOn: Bool { preferences.reminders.isEnabled || NightShiftPreview.isActive }

    /// Whether this iPhone can ring the reminder as an alarm (iOS 26 and later).
    var supportsAlarm: Bool { alarms.isSupported || NightShiftPreview.showsAlarmToggle }

    func reminderContext() -> NightShiftReminderContext {
        let now = clock.now
        let duty = duty(at: now)
        var context = NightShiftReminderContext(duty: duty, ringsAsAlarm: preferences.nightShiftAlarm && alarms.isSupported)
        guard hasPartner, let shift = store.shift, let me = store.me else { return context }
        if case .offDuty(let until) = duty {
            context.summary = NightSummary(shift: shift, feeds: recentFeeds())
            context.summaryAt = until
        } else if duty == .none, store.shouldNotifyEarlyEnd(of: shift, me: me, at: now) {
            // The partner tapped End: the notification scheduled for the morning is gone with the
            // shift, so this phone says it now, once.
            context.summary = NightSummary(shift: shift, feeds: recentFeeds())
            context.summaryAt = now.addingTimeInterval(1)
            store.markEarlyEndNotified(shift)
        }
        return context
    }

    private func recentFeeds() -> [FeedEntry] {
        guard let context = modelContainer?.mainContext else { return [] }
        return ((try? context.fetch(FeedingSession.completedFeeds(limit: 60))) ?? []).compactMap(\.feedEntry)
    }

    // MARK: - Actions

    /// "Start on-call", and "Take over" when the other parent is on duty.
    func goOnDuty() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        guard let me = await identity() else {
            errorMessage = String(localized: "Newbee couldn't reach iCloud to start your shift. Check your connection and try again.")
            return
        }
        let now = clock.now
        if let running = store.shift, running.isRunning(at: now) {
            store.set(running.takenOver(by: me, at: now))
        } else {
            store.set(NightShift.starting(for: me, at: now, schedule: schedule))
        }
        // The shift is about reminders: ask now if the parent was never asked.
        if reminders?.permission == .notDetermined {
            await reminders?.requestPermission()
        }
    }

    /// "End shift": both phones go back to their usual reminders now.
    func endShift() {
        let now = clock.now
        guard let shift = store.shift, shift.isRunning(at: now) else { return }
        store.set(shift.ended(at: now))
    }

    func dismissSummary(of shift: NightShift) {
        store.dismissSummary(of: shift)
    }

    /// Turns "Ring as alarm" on or off. Turning it on asks iOS for permission; returns `false`
    /// (and leaves it off) when alarms aren't allowed.
    @discardableResult
    func setAlarm(_ isOn: Bool) async -> Bool {
        if isOn, await !alarms.requestPermission() {
            preferences.nightShiftAlarm = false
            return false
        }
        preferences.nightShiftAlarm = isOn
        await reminders?.reschedule()
        return true
    }

    // MARK: - Who this parent is

    /// Asks iCloud once and remembers the answer.
    func refreshIdentity() async {
        guard let engine, let id = try? await engine.userID() else { return }
        store.setMe(id)
    }

    /// The iCloud account changed: whoever this was, they aren't any more.
    func forgetIdentity() {
        store.setMe(nil)
        Task { await refreshIdentity() }
    }

    private func identity() async -> String? {
        if let me = store.me { return me }
        await refreshIdentity()
        return store.me
    }
}

/// UI tests and screenshots show a Night Shift card without a partner or iCloud:
/// `-nightShiftPreview offerStart|onDuty|partnerOnDuty|summary`.
enum NightShiftPreview {
    static var isActive: Bool {
        AppConfiguration.isUITesting && UserDefaults.standard.string(forKey: "nightShiftPreview") != nil
    }

    /// Screenshots on iOS 26 show the "Ring as alarm" toggle, which only the real app can use.
    static var showsAlarmToggle: Bool {
        guard isActive else { return false }
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static func card(at now: Date) -> NightShiftCard? {
        guard AppConfiguration.isUITesting,
              let value = UserDefaults.standard.string(forKey: "nightShiftPreview") else { return nil }
        let morning = NightShiftSchedule().morning(after: now)
        switch value {
        case "offerStart": return .offerStart
        case "onDuty": return .onDuty(until: morning)
        case "partnerOnDuty": return .partnerOnDuty(until: morning)
        case "summary":
            // The ten hours up to half an hour ago, so the sample feeds fall inside it.
            let end = now.addingTimeInterval(-1_800)
            return .summary(NightShift(onDuty: "partner", startedAt: end.addingTimeInterval(-10 * 3_600), endsAt: end, changedAt: end))
        default: return nil
        }
    }
}
