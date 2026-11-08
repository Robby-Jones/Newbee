import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Home (docs/UX_SPEC.md §3.2), laid out like the home screens of popular baby trackers: who
/// the baby is, how long since the last feed, three big round buttons (Breastfeed, Bottle,
/// Pumping), today's totals and the latest entries. Answers the 3 a.m. questions in
/// one glance; everything older lives in History and Insights.
struct DashboardView: View {
    @Environment(FeedingSessionUIModel.self) private var sessionModel: FeedingSessionUIModel?
    /// Enough recent feeds for "today" and the rolling 24 hours, even on a very busy day.
    @Query(FeedingSession.completedFeeds(limit: 80)) private var recent: [FeedingSession]
    @Query(sort: \Baby.createdAt) private var babies: [Baby]

    var body: some View {
        let entries = recent.compactMap(\.feedEntry)
        // Minute ticks keep "2 h 14 min ago" and the day boundary current without per-second work.
        TimelineView(.everyMinute) { context in
            // The tick's date is the start of the minute; a feed logged since then would count
            // as "in the future" and be left out, so use the real time.
            let now = max(context.date, .now)
            let summary = DashboardSummary(entries: entries, now: now)
            ScrollView {
                VStack(spacing: NBSpacing.xl) {
                    ProfileHeader(baby: babies.first, now: now)
                    if let sessionModel, sessionModel.activeSession != nil {
                        ActiveFeedCard(model: sessionModel)
                    } else {
                        LastFeedCard(summary: summary, now: now)
                    }
                    QuickActions(now: now)
                    TodaySection(summary: summary)
                    RecentSection(entries: Array(entries.filter { $0.start <= now }.prefix(3)))
                }
                .padding(.horizontal, NBSpacing.l)
                .padding(.vertical, NBSpacing.m)
            }
        }
        .background(NBColor.canvas)
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
    }

    static func greeting(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: String(localized: "Good morning")
        case 12..<17: String(localized: "Good afternoon")
        case 17..<22: String(localized: "Good evening")
        default: String(localized: "Hello, night owl")
        }
    }

    /// "2 h ago", "14 min ago", "just now": short enough to sit under a round button.
    static func compactAgo(_ interval: TimeInterval) -> String {
        if interval < 60 { return String(localized: "just now") }
        if interval < 3_600 { return String(localized: "\(Int(interval / 60)) min ago") }
        return String(localized: "\(Int(interval / 3_600)) h ago")
    }
}

/// The baby's photo, name and age from Settings, or a greeting when there's no profile yet.
private struct ProfileHeader: View {
    let baby: Baby?
    let now: Date
    @Environment(BabyPhotoStore.self) private var photo: BabyPhotoStore?

    var body: some View {
        let name = baby?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let image = photo?.image
        VStack(spacing: NBSpacing.s) {
            // The photo from Settings is shown larger than the placeholder heart.
            BabyAvatar(image: image, size: image == nil ? 64 : 112)
                .overlay {
                    if image != nil {
                        Circle().strokeBorder(NBColor.accent.opacity(0.35), lineWidth: 3)
                    }
                }
            Text(name.isEmpty ? DashboardView.greeting(at: now) : name)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let birthDate = baby?.birthDate {
                Text(BabyAge.text(from: birthDate, now: now))
                    .font(.subheadline)
                    .foregroundStyle(NBColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NBSpacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// "Time since last feed · 2 h 14 min · Breast · L 12 min · R 9 min · 9:41 PM", centered and large.
/// The side to start on next is marked on the round buttons below, not repeated here.
private struct LastFeedCard: View {
    let summary: DashboardSummary
    let now: Date
    /// Settings' "Count from"; a change redraws the card straight away.
    @Environment(AppPreferences.self) private var preferences: AppPreferences?

    var body: some View {
        Card {
            VStack(spacing: NBSpacing.s) {
                if let last = summary.lastFeed,
                   let since = summary.timeSinceLastFeed(at: now, countingFrom: preferences?.reminders.basis ?? .start) {
                    Text("Time since last feed")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(NBColor.secondaryText)
                    Text(since < 60 ? String(localized: "Just now") : DurationText.short(since))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .accessibilityLabel(FeedText.ago(since))
                    Text(detail(last))
                        .font(.subheadline)
                        .foregroundStyle(NBColor.secondaryText)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No feeds yet")
                        .font(.title2.weight(.bold))
                    Text("Tap Breastfeed or Bottle below to log the first one.")
                        .font(.subheadline)
                        .foregroundStyle(NBColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NBSpacing.s)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ entry: FeedEntry) -> String {
        let time = entry.start.formatted(.dateTime.hour().minute())
        if let sides = FeedText.sides(entry) {
            return String(localized: "Breast · \(sides) · \(time)")
        }
        return "\(FeedText.title(entry)) · \(time)"
    }
}

/// The running feed in place of the Time since last feed card. Tapping it opens the timer.
private struct ActiveFeedCard: View {
    let model: FeedingSessionUIModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let display = model.display(at: context.date)
            Button {
                model.openTimer()
            } label: {
                Card {
                    VStack(spacing: NBSpacing.s) {
                        HStack(spacing: NBSpacing.xs) {
                            if let side = display.activeSide {
                                LiveDot(color: NBColor.side(side))
                            } else {
                                Image(systemName: "pause.fill")
                            }
                            Text(display.isPaused ? "Feed paused" : "Feeding now")
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(NBColor.secondaryText)
                        TimerText(display.total, size: 44, relativeTo: .largeTitle)
                        Text("L \(DurationText.clock(display.left)) · R \(DurationText.clock(display.right))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(NBColor.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NBSpacing.s)
                }
            }
            .buttonStyle(PressableButtonStyle())
            .foregroundStyle(Color.primary)
            .accessibilityHint("Opens the feeding timer")
        }
    }
}

/// Breastfeed, Bottle and Pumping as big round buttons with when each was last used.
///
/// Breastfeed opens the alternating Left / Right timer, where the parent picks the side (the
/// suggested one is marked there). While a feed runs it just reopens the timer, so a tap on
/// Home never switches sides by accident.
private struct QuickActions: View {
    let now: Date

    @Environment(FeedingSessionUIModel.self) private var sessionModel: FeedingSessionUIModel?
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: NBSpacing.l))
            : AnyLayout(HStackLayout(alignment: .top, spacing: NBSpacing.m))
        layout {
            if let sessionModel {
                breastfeedAction(sessionModel)
            }
            if let bottleModel {
                bottleAction(bottleModel)
            }
            if let pumpModel {
                pumpAction(pumpModel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NBSpacing.s)
        .onAppear {
            bottleModel?.refresh()
            pumpModel?.refresh()
        }
    }

    private func breastfeedAction(_ model: FeedingSessionUIModel) -> some View {
        let active = model.activeSession
        let running = active?.status == .active
        let caption: String = if let active {
            active.status == .active ? String(localized: "Feeding") : String(localized: "Paused")
        } else {
            String(localized: "Next: \(model.controller.suggestedNextSide.title)")
        }
        let side = active?.openSegment?.side ?? .left
        return QuickActionCircle(
            title: String(localized: "Breastfeed"),
            systemImage: active == nil ? "heart.fill" : "timer",
            tint: NBColor.side(side),
            ink: NBColor.sideInk(side),
            filled: running,
            badge: nil,
            caption: caption
        ) {
            model.openTimer()
        }
        .accessibilityLabel(String(localized: "Breastfeed"))
        .accessibilityValue(caption)
        .accessibilityHint(active == nil
            ? String(localized: "Opens the Left and Right timer")
            : String(localized: "Opens the feeding timer"))
        .accessibilityIdentifier("breastfeedButton")
    }

    private func bottleAction(_ model: BottleLogUIModel) -> some View {
        let caption = model.recent.first.map { DashboardView.compactAgo(now.timeIntervalSince($0.startedAt)) }
            ?? String(localized: "Not yet")
        return QuickActionCircle(
            title: String(localized: "Bottle"),
            systemImage: "waterbottle.fill",
            tint: NBColor.bottleBreastMilk,
            ink: NBColor.bottleBreastMilkInk,
            filled: false,
            badge: nil,
            caption: caption
        ) {
            model.presentNew()
        }
        // Today's bottles stay in the label for VoiceOver (and the UI tests).
        .accessibilityLabel(String(localized: "Log bottle, \(model.todayLine)"))
        .accessibilityIdentifier("logBottleButton")
    }

    private func pumpAction(_ model: PumpLogUIModel) -> some View {
        let caption = model.latest.map { DashboardView.compactAgo(now.timeIntervalSince($0.startedAt)) }
            ?? String(localized: "Not yet")
        return QuickActionCircle(
            title: String(localized: "Pumping"),
            systemImage: PumpText.symbolName,
            tint: NBColor.pump,
            ink: NBColor.pumpInk,
            filled: false,
            badge: nil,
            caption: caption
        ) {
            model.presentNew()
        }
        .accessibilityLabel(String(localized: "Log pumping, \(model.todayLine)"))
        .accessibilityIdentifier("logPumpButton")
    }
}

/// A big round action with a caption underneath ("2 h ago").
private struct QuickActionCircle: View {
    let title: String
    let systemImage: String
    /// Fill and outline color.
    let tint: Color
    /// Icon color on the card (a darker `tint` in light mode, for contrast).
    let ink: Color
    let filled: Bool
    let badge: String?
    let caption: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 92

    var body: some View {
        Button(action: action) {
            VStack(spacing: NBSpacing.s) {
                VStack(spacing: NBSpacing.xs) {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(filled ? NBColor.onSide : ink)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(filled ? NBColor.onSide : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: diameter, height: diameter)
                .background {
                    if filled {
                        Circle().fill(tint)
                    } else {
                        Circle().fill(NBColor.card)
                            .overlay { Circle().strokeBorder(tint, lineWidth: 2) }
                    }
                }
                .overlay(alignment: .top) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary))
                            .foregroundStyle(NBColor.canvas)
                            .offset(y: -9)
                    }
                }
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(NBColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Today's totals in one compact card, and the rolling 24-hour line.
private struct TodaySection: View {
    let summary: DashboardSummary
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?

    var body: some View {
        VStack(alignment: .leading, spacing: NBSpacing.m) {
            Text("Today")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Card(padding: NBSpacing.m) {
                HStack(alignment: .top, spacing: NBSpacing.s) {
                    stat(String(localized: "Feeds"), "drop.fill", NBColor.accent, "\(summary.today.feedCount)")
                    stat(String(localized: "Breast"), "heart.fill", NBColor.leftInk, DurationText.short(summary.today.breastDuration))
                    stat(String(localized: "Bottles"), "waterbottle.fill", NBColor.bottleBreastMilkInk, FeedText.volume(ml: summary.today.bottleML, unit: bottleModel?.unit ?? .milliliters))
                    stat(String(localized: "Avg gap"), "clock.fill", NBColor.rightInk, summary.today.averageInterval.map(DurationText.short) ?? "–")
                }
            }
            Text(last24Line)
                .font(.footnote)
                .foregroundStyle(NBColor.secondaryText)
        }
    }

    /// Tinted symbol, value, label. The tint is on the symbol only, so the text keeps full contrast.
    private func stat(_ label: String, _ systemImage: String, _ tint: Color, _ value: String) -> some View {
        VStack(spacing: NBSpacing.xs) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(NBColor.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var last24Line: String {
        let totals = summary.last24Hours
        guard let interval = totals.averageInterval else {
            return String(localized: "Last 24 h: \(totals.feedCount) feeds")
        }
        return String(localized: "Last 24 h: \(totals.feedCount) feeds · average gap \(DurationText.short(interval))")
    }
}

/// The latest few entries, with their notes. Everything older is in History.
private struct RecentSection: View {
    let entries: [FeedEntry]

    var body: some View {
        let rows = FeedTimeline.days(from: entries).flatMap(\.rows)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                Text("Recent")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().padding(.leading, NBSpacing.l) }
                            FeedRow(row: row)
                                .padding(.horizontal, NBSpacing.l)
                                .padding(.vertical, NBSpacing.s)
                        }
                    }
                }
            }
        }
    }
}

#Preview("Idle") {
    let container = try! PersistenceController.makeContainer(.inMemory)
    HistoryPreviewData.insert(into: container.mainContext)
    return NavigationStack { DashboardView() }
        .modelContainer(container)
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
        .environment(BottleLogUIModel.preview())
        .environment(PumpLogUIModel.preview())
}

#Preview("Empty") {
    NavigationStack { DashboardView() }
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
}

#Preview("Feeding") {
    NavigationStack { DashboardView() }
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.activeFixture()))
}
