import Foundation
import NewbeeKit
import Observation

/// Keeps pending local notifications in line with the feeding data and Settings
/// (docs/PRD.md #16 and #22). Implements NewbeeKit's `ReminderScheduling`, which
/// `FeedingSessionManager` calls after every breastfeeding change.
///
/// Every pass reads the store afresh, asks `ReminderPlanner` what should be pending, and replaces
/// Newbee's pending requests with exactly that. Passes run one at a time, in call order, so
/// overlapping triggers (a feed ending, a bottle saved, the app coming forward) can't leave a
/// stale reminder behind.
@MainActor
@Observable
final class ReminderScheduler: ReminderScheduling {
    /// Whether notifications are allowed, as of the last pass.
    private(set) var permission: NotificationPermission = .notDetermined
    /// What is scheduled now, so Settings can say when the next reminder is.
    private(set) var pending: [PlannedReminder] = []

    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let feedingRepository: any FeedingRepository
    @ObservationIgnored private let bottleRepository: any BottleRepository
    @ObservationIgnored private let client: any NotificationClient
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let planner: ReminderPlanner
    @ObservationIgnored private var tail: Task<Void, Never>?

    init(
        preferences: AppPreferences,
        feedingRepository: any FeedingRepository,
        bottleRepository: any BottleRepository,
        client: any NotificationClient,
        clock: any AppClock,
        planner: ReminderPlanner = ReminderPlanner()
    ) {
        self.preferences = preferences
        self.feedingRepository = feedingRepository
        self.bottleRepository = bottleRepository
        self.client = client
        self.clock = clock
        self.planner = planner
    }

    // MARK: - ReminderScheduling

    func feedingDataDidChange(activeSession: SessionSnapshot?, lastCompletedSession: SessionSnapshot?) async {
        // The store already holds these; `reschedule` reads it so bottles count too.
        await reschedule()
    }

    // MARK: - Commands

    /// Recomputes and replaces pending reminders. Call after any feed or setting changes.
    func reschedule() async {
        await enqueue { [weak self] in await self?.rescheduleNow() }
    }

    /// Asks for notification permission (the system prompt appears once), then reschedules.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = await client.requestPermission()
        await reschedule()
        return granted
    }

    /// Removes every pending and delivered Newbee notification.
    func removeAll() async {
        await enqueue { [weak self] in
            guard let self else { return }
            await client.removeAll()
            pending = []
        }
    }

    // MARK: - Internals

    private func enqueue(_ work: @escaping @MainActor @Sendable () async -> Void) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        tail = task
        await task.value
    }

    private func rescheduleNow() async {
        permission = await client.permission()
        let now = clock.now
        let active = try? feedingRepository.activeSession()
        let lastBreast = (try? feedingRepository.recentCompletedSessions(limit: 1))?.first
        let lastBottle = (try? bottleRepository.recentBottles(limit: 1))?.first
        let lastFeed = LastFeed.latest(breast: lastBreast, bottle: lastBottle)
        let plan = permission == .allowed
            ? planner.plan(settings: preferences.reminders, lastFeed: lastFeed, active: active, now: now)
            : []
        let identifiers = PlannedReminder.Kind.allCases.map(PlannedReminder.identifier(for:))
        let settings = preferences.reminders
        let notifications = plan.map { Self.notification(for: $0, basis: settings.basis, interval: settings.interval) }
        await client.replace(identifiers: identifiers, with: notifications)
        pending = plan
    }

    // MARK: - Wording

    /// Calm, non-prescriptive wording (docs/PRD.md: "Not medical advice").
    static func notification(for reminder: PlannedReminder, basis: ReminderSettings.Basis, interval: TimeInterval) -> ScheduledNotification {
        let time = reminder.anchor.formatted(date: .omitted, time: .shortened)
        let title: String
        let body: String
        switch reminder.kind {
        case .feedDue:
            title = String(localized: "Feeding reminder")
            let since = switch basis {
            case .start: String(localized: "The last feed started at \(time).")
            case .end: String(localized: "The last feed ended at \(time).")
            }
            body = reminder.deferredByQuietHours
                ? String(localized: "\(since) Held until quiet hours ended.")
                : String(localized: "It's been \(DurationText.short(interval)). \(since)")
        case .stillFeeding:
            title = String(localized: "Still feeding?")
            let elapsed = DurationText.short(reminder.fireDate.timeIntervalSince(reminder.anchor))
            if let side = reminder.side {
                body = String(localized: "The timer has been on the \(side.title.lowercased()) side for \(elapsed). Open Newbee to end the feed or keep going.")
            } else {
                body = String(localized: "The feed has been paused for \(elapsed). Open Newbee to end it or keep going.")
            }
        }
        return ScheduledNotification(identifier: reminder.identifier, title: title, body: body, fireDate: reminder.fireDate)
    }
}
