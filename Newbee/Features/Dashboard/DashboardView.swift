import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Home (docs/UX_SPEC.md §3.2), laid out like the home screens of popular baby trackers: who
/// the baby is, how long since the last feed, three big round buttons to start a feed on either
/// side or log a bottle, today's totals and the latest entries. Answers the 3 a.m. questions in
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
                    QuickActions(entries: entries, now: now)
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

/// The baby's name and age from Settings, or a greeting when there's no profile yet.
private struct ProfileHeader: View {
    let baby: Baby?
    let now: Date

    var body: some View {
        let name = baby?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(spacing: NBSpacing.s) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundStyle(NBColor.accent)
                .frame(width: 64, height: 64)
                .background(NBColor.accent.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            Text(name.isEmpty ? DashboardView.greeting(at: now) : name)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let birthDate = baby?.birthDate {
                Text(BabyAge.text(from: birthDate, now: now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NBSpacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// "Last fed · 2 h 14 min · Breast · L 12 min · R 9 min · 9:41 PM", centered and large.
/// The side to start on next is marked on the round buttons below, not repeated here.
private struct LastFeedCard: View {
    let summary: DashboardSummary
    let now: Date

    var body: some View {
        Card {
            VStack(spacing: NBSpacing.s) {
                if let last = summary.lastFeed, let since = summary.timeSinceLastFeed(at: now) {
                    Text("Last fed")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(since < 60 ? String(localized: "Just now") : DurationText.short(since))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .accessibilityLabel(FeedText.ago(since))
                    Text(detail(last))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No feeds yet")
                        .font(.title2.weight(.bold))
                    Text("Tap Left, Right or Bottle below to log the first one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

/// The running feed in place of the Last fed card. Tapping it opens the timer.
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
                        .foregroundStyle(.secondary)
                        TimerText(display.total, size: 44, relativeTo: .largeTitle)
                        Text("L \(DurationText.clock(display.left)) · R \(DurationText.clock(display.right))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
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

/// Left, Right and Bottle as big round buttons with when each was last used.
///
/// With no feed running, Left and Right start one on that side (the suggested side is filled
/// and tagged) and open the timer. While a feed runs they just open the timer, so a tap on Home
/// never switches sides by accident.
private struct QuickActions: View {
    let entries: [FeedEntry]
    let now: Date

    @Environment(FeedingSessionUIModel.self) private var sessionModel: FeedingSessionUIModel?
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: NBSpacing.l))
            : AnyLayout(HStackLayout(alignment: .top, spacing: NBSpacing.m))
        layout {
            if let sessionModel {
                ForEach(Side.allCases, id: \.self) { side in
                    sideAction(side, model: sessionModel)
                }
            }
            if let bottleModel {
                bottleAction(bottleModel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NBSpacing.s)
        .onAppear { bottleModel?.refresh() }
    }

    private func sideAction(_ side: Side, model: FeedingSessionUIModel) -> some View {
        let active = model.activeSession
        let running = active?.status == .active && active?.openSegment?.side == side
        let suggested = active == nil && model.controller.suggestedNextSide == side
        let caption: String = if active != nil {
            running ? String(localized: "Feeding") : String(localized: "Open timer")
        } else {
            lastUsed(side).map { DashboardView.compactAgo(now.timeIntervalSince($0)) } ?? String(localized: "Not yet")
        }
        return QuickActionCircle(
            title: side.title,
            systemImage: active == nil ? "play.fill" : "timer",
            tint: NBColor.side(side),
            filled: suggested || running,
            badge: suggested ? String(localized: "Suggested") : nil,
            caption: caption
        ) {
            if active == nil {
                model.startFromHome(side: side)
            } else {
                model.openTimer()
            }
        }
        .accessibilityLabel(String(localized: "\(side.title) side"))
        .accessibilityValue(suggested ? "\(String(localized: "suggested")), \(caption)" : caption)
        .accessibilityHint(active == nil
            ? String(localized: "Starts a feed on the \(side.title.lowercased()) side")
            : String(localized: "Opens the feeding timer"))
        .accessibilityIdentifier("sideButton.\(side.rawValue)")
    }

    private func bottleAction(_ model: BottleLogUIModel) -> some View {
        let caption = model.recent.first.map { DashboardView.compactAgo(now.timeIntervalSince($0.startedAt)) }
            ?? String(localized: "Not yet")
        return QuickActionCircle(
            title: String(localized: "Bottle"),
            systemImage: "waterbottle.fill",
            tint: NBColor.bottleBreastMilk,
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

    /// When `side` was last fed from, from finished feeds.
    private func lastUsed(_ side: Side) -> Date? {
        entries
            .filter { $0.start <= now && $0.duration(on: side) > 0 }
            .map(\.start)
            .max()
    }
}

/// A big round action with a caption underneath ("2 h ago").
private struct QuickActionCircle: View {
    let title: String
    let systemImage: String
    let tint: Color
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
                        .foregroundStyle(filled ? NBColor.onSide : tint)
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
                            .overlay { Circle().strokeBorder(tint.opacity(0.6), lineWidth: 2) }
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
                    .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: NBSpacing.m) {
            Text("Today")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Card(padding: NBSpacing.m) {
                HStack(alignment: .top, spacing: NBSpacing.s) {
                    stat(String(localized: "Feeds"), "drop.fill", NBColor.accent, "\(summary.today.feedCount)")
                    stat(String(localized: "Breast"), "heart.fill", NBColor.left, DurationText.short(summary.today.breastDuration))
                    stat(String(localized: "Bottles"), "waterbottle.fill", NBColor.bottleBreastMilk, FeedText.volume(ml: summary.today.bottleML))
                    stat(String(localized: "Avg gap"), "clock.fill", NBColor.right, summary.today.averageInterval.map(DurationText.short) ?? "–")
                }
            }
            Text(last24Line)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
