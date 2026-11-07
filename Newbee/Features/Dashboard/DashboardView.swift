import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Home (docs/UX_SPEC.md §3.2): how long ago the last feed was, the Start buttons (or the
/// running feed), Log bottle, and today's totals. Answers the 3 a.m. questions in one glance;
/// everything older lives in History and Insights.
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
                VStack(alignment: .leading, spacing: NBSpacing.l) {
                    if let profile = profileLine(at: now) {
                        Text(profile)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, -NBSpacing.s)
                    }
                    if sessionModel?.activeSession == nil {
                        LastFeedCard(summary: summary, now: now)
                    }
                    VStack(alignment: .leading, spacing: NBSpacing.m) {
                        if let sessionModel {
                            BreastfeedingQuickStart(model: sessionModel)
                        }
                        BottleQuickLogCard()
                    }
                    TodaySection(summary: summary)
                }
                .padding(NBSpacing.l)
            }
            .navigationTitle(Self.greeting(at: now))
        }
        .background(NBColor.canvas)
    }

    /// "Ava · 3 wk 2 d old" from the profile in Settings, when there is one.
    private func profileLine(at now: Date) -> String? {
        guard let baby = babies.first else { return nil }
        let name = baby.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let age = baby.birthDate.map { BabyAge.text(from: $0, now: now) }
        let parts = [name.isEmpty ? nil : name, age].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func greeting(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: String(localized: "Good morning")
        case 12..<17: String(localized: "Good afternoon")
        case 17..<22: String(localized: "Good evening")
        default: String(localized: "Hello, night owl")
        }
    }
}

/// "Last feed: 2 h 14 min ago · 9:41 PM · Breast · L 12 min · R 9 min". The side to start on
/// next is shown on the Start buttons below, not repeated here.
private struct LastFeedCard: View {
    let summary: DashboardSummary
    let now: Date

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.s) {
                if let last = summary.lastFeed, let since = summary.timeSinceLastFeed(at: now) {
                    Label {
                        Text("Last feed")
                    } icon: {
                        Image(systemName: last.symbolName)
                            .foregroundStyle(last.tint)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Text(FeedText.ago(since))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(detail(last))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No feeds yet")
                        .font(.title2.weight(.bold))
                    Text("Tap a side to start timing, or log a bottle.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ entry: FeedEntry) -> String {
        let time = entry.start.formatted(.dateTime.hour().minute())
        if let sides = FeedText.sides(entry) {
            return String(localized: "\(time) · Breast · \(sides)")
        }
        return "\(time) · \(FeedText.title(entry))"
    }
}

/// Today's tiles and the rolling 24-hour line.
private struct TodaySection: View {
    let summary: DashboardSummary

    private let columns = [GridItem(.flexible(), spacing: NBSpacing.m), GridItem(.flexible(), spacing: NBSpacing.m)]

    var body: some View {
        VStack(alignment: .leading, spacing: NBSpacing.m) {
            Text("Today")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: NBSpacing.m) {
                StatTile(title: String(localized: "Feeds"), systemImage: "drop.fill", tint: NBColor.accent,
                         value: "\(summary.today.feedCount)")
                StatTile(title: String(localized: "Breastfeeding"), systemImage: "heart.fill", tint: NBColor.left,
                         value: DurationText.short(summary.today.breastDuration))
                StatTile(title: String(localized: "Bottles"), systemImage: "waterbottle.fill", tint: NBColor.bottleBreastMilk,
                         value: FeedText.volume(ml: summary.today.bottleML))
                StatTile(title: String(localized: "Average gap"), systemImage: "clock.fill", tint: NBColor.right,
                         value: summary.today.averageInterval.map(DurationText.short) ?? "–")
            }
            Text(last24Line)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var last24Line: String {
        let totals = summary.last24Hours
        guard let interval = totals.averageInterval else {
            return String(localized: "Last 24 h: \(totals.feedCount) feeds")
        }
        return String(localized: "Last 24 h: \(totals.feedCount) feeds · average gap \(DurationText.short(interval))")
    }
}

/// Apple Health-style summary tile: a tinted symbol and label, then the value.
/// The tint is on the symbol only, so the text keeps full contrast.
private struct StatTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    let value: String

    var body: some View {
        Card(padding: NBSpacing.m) {
            VStack(alignment: .leading, spacing: NBSpacing.s) {
                Label {
                    Text(title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                .font(.footnote.weight(.semibold))
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Start buttons with the suggested side emphasised, or a live card while a feed is running.
struct BreastfeedingQuickStart: View {
    let model: FeedingSessionUIModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let display = model.display(at: context.date)
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                switch display.phase {
                case .notStarted:
                    Text("Start a feed")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: NBSpacing.m))
                        : AnyLayout(HStackLayout(spacing: NBSpacing.m))
                    layout {
                        ForEach(Side.allCases, id: \.self) { side in
                            SideButton(side: side, mode: display.mode(for: side), elapsed: nil) {
                                model.startFromHome(side: side)
                            }
                        }
                    }
                case .active, .paused:
                    activeCard(display)
                }
            }
        }
    }

    private func activeCard(_ display: BreastfeedingTimerDisplay) -> some View {
        Button {
            model.openTimer()
        } label: {
            Card {
                HStack(spacing: NBSpacing.m) {
                    if let side = display.activeSide {
                        SideBadge(side: side)
                    } else {
                        Image(systemName: "pause.circle.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: NBSpacing.xs) {
                        Text(display.isPaused ? "Feed paused" : "Feeding now")
                            .font(.headline)
                        Text("L \(DurationText.clock(display.left)) · R \(DurationText.clock(display.right))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TimerText(display.total, size: 28, relativeTo: .title2)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(Color.primary)
        .accessibilityHint("Opens the feeding timer")
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
