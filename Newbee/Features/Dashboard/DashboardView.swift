import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Home (docs/UX_SPEC.md §3.2): when the last feed was and how long ago, the side to start on,
/// the Start buttons (or the running feed), and today's totals.
struct DashboardView: View {
    @Environment(FeedingSessionUIModel.self) private var sessionModel: FeedingSessionUIModel?
    /// Enough recent feeds for "today" and the rolling 24 hours, even on a very busy day.
    @Query(FeedingSession.completedFeeds(limit: 80)) private var recent: [FeedingSession]
    var body: some View {
        let entries = recent.compactMap(\.feedEntry)
        // Minute ticks keep "2 h 14 min ago" and the day boundary current without per-second work.
        TimelineView(.everyMinute) { context in
            let summary = DashboardSummary(entries: entries, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: NBSpacing.l) {
                    if sessionModel?.activeSession == nil {
                        LastFeedCard(summary: summary, suggestedSide: sessionModel?.controller.suggestedNextSide, now: context.date)
                    }
                    if let sessionModel {
                        BreastfeedingQuickStart(model: sessionModel)
                    }
                    // "Log bottle" with today's bottle total and the last few bottles.
                    BottleQuickLogCard()
                    TodaySection(summary: summary)
                }
                .padding(NBSpacing.l)
            }
            .navigationTitle(Self.greeting(at: context.date))
        }
        .background(NBColor.canvas)
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

/// "Last feed: 2 h 14 min ago · 9:41 PM · Breast · L 12 min R 9 min · Next side R".
private struct LastFeedCard: View {
    let summary: DashboardSummary
    /// The session manager's suggestion, which the Start buttons also use.
    let suggestedSide: Side?
    let now: Date

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.s) {
                Text("Last feed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let last = summary.lastFeed, let since = summary.timeSinceLastFeed(at: now) {
                    Text(FeedText.ago(since))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(detail(last))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    nextSide
                } else {
                    Text("No feeds yet")
                        .font(.title2.weight(.bold))
                    Text("Start your first one below.")
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

    private var nextSide: some View {
        let side = suggestedSide ?? summary.suggestedNextSide
        return HStack(spacing: NBSpacing.s) {
            Text("Next side")
                .font(.subheadline)
            SideBadge(side: side)
            Text(side.title)
                .font(.subheadline.weight(.semibold))
            Text("suggested")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, NBSpacing.xs)
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
            LazyVGrid(columns: columns, spacing: NBSpacing.m) {
                StatTile(value: "\(summary.today.feedCount)", label: summary.today.feedCount == 1 ? String(localized: "feed") : String(localized: "feeds"))
                StatTile(value: DurationText.short(summary.today.breastDuration), label: String(localized: "breastfeeding"))
                StatTile(value: FeedText.volume(ml: summary.today.bottleML), label: String(localized: "from bottles"))
                StatTile(
                    value: summary.today.averageInterval.map(DurationText.short) ?? "–",
                    label: String(localized: "average gap")
                )
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

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        Card(padding: NBSpacing.m) {
            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                    Text("Breastfeed")
                        .font(.title3.weight(.semibold))
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
