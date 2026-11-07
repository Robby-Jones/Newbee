import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Tools (docs/UX_SPEC.md §3.9): interval calculator, side tracker, quick stats, export and
/// Settings.
struct ToolsView: View {
    /// A week of feeds even on a very busy week, plus some for the interval picker.
    @Query(FeedingSession.completedFeeds(limit: 200)) private var recent: [FeedingSession]

    var body: some View {
        let entries = recent.compactMap(\.feedEntry)
        TimelineView(.everyMinute) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: NBSpacing.l) {
                    SinceLastFeedCard(last: entries.first, now: context.date)
                    IntervalCalculatorCard(entries: Array(entries.prefix(30)))
                    SideTrackerCard(tracker: SideTracker(entries: entries))
                    QuickStatsCard(stats: QuickStats(entries: entries, now: context.date))
                    MoreLinks()
                }
                .padding(NBSpacing.l)
            }
        }
        .background(NBColor.canvas)
        .navigationTitle("Tools")
    }
}

// MARK: - Interval calculator

private struct ToolHeader: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

/// "Since last feed": from its start and from its end.
private struct SinceLastFeedCard: View {
    let last: FeedEntry?
    let now: Date

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                ToolHeader(title: "Since last feed", systemImage: "clock")
                if let last {
                    HStack(alignment: .firstTextBaseline, spacing: NBSpacing.xl) {
                        figure(IntervalCalculator.since(last, at: now, basis: .startToStart), label: String(localized: "since it started"))
                        figure(IntervalCalculator.since(last, at: now, basis: .endToStart), label: String(localized: "since it ended"))
                    }
                    Text("\(last.start.formatted(date: .omitted, time: .shortened)) · \(FeedText.title(last))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No feeds yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ interval: TimeInterval, label: String) -> some View {
        VStack(alignment: .leading, spacing: NBSpacing.xs) {
            Text(DurationText.short(interval))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// The interval between any two recent feeds.
private struct IntervalCalculatorCard: View {
    let entries: [FeedEntry]
    @State private var firstID: UUID?
    @State private var secondID: UUID?
    @State private var basis: IntervalBasis = .startToStart

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                ToolHeader(title: "Interval between feeds", systemImage: "arrow.left.and.right")
                if entries.count < 2 {
                    Text("Log two feeds to compare them.")
                        .foregroundStyle(.secondary)
                } else {
                    let first = entry(firstID) ?? entries[1]
                    let second = entry(secondID) ?? entries[0]
                    feedPicker("From", selection: Binding(get: { first.id }, set: { firstID = $0 }))
                    feedPicker("To", selection: Binding(get: { second.id }, set: { secondID = $0 }))
                    Picker("Measure", selection: $basis) {
                        Text("Start to start").tag(IntervalBasis.startToStart)
                        Text("End to start").tag(IntervalBasis.endToStart)
                    }
                    .pickerStyle(.segmented)
                    Text(DurationText.short(IntervalCalculator.interval(between: first, and: second, basis: basis)))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .accessibilityLabel(DurationText.spoken(IntervalCalculator.interval(between: first, and: second, basis: basis)))
                }
            }
        }
    }

    private func entry(_ id: UUID?) -> FeedEntry? {
        id.flatMap { id in entries.first { $0.id == id } }
    }

    private func feedPicker(_ title: LocalizedStringKey, selection: Binding<UUID>) -> some View {
        Picker(title, selection: selection) {
            ForEach(entries) { entry in
                Text("\(FeedText.dayTitle(entry.start)) \(entry.start.formatted(date: .omitted, time: .shortened)) · \(FeedText.title(entry))")
                    .tag(entry.id)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Side tracker

private struct SideTrackerCard: View {
    let tracker: SideTracker

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                ToolHeader(title: "Side tracker", systemImage: "arrow.triangle.swap")
                HStack(spacing: NBSpacing.xl) {
                    labelled(String(localized: "Last side")) {
                        if let last = tracker.lastSide {
                            SideBadge(side: last, style: .soft)
                        } else {
                            Text("–")
                        }
                    }
                    labelled(String(localized: "Start next on")) {
                        HStack(spacing: NBSpacing.s) {
                            SideBadge(side: tracker.suggestedNextSide)
                            Text(tracker.suggestedNextSide.title).font(.headline)
                        }
                    }
                }
                if !tracker.recentStartingSides.isEmpty {
                    labelled(String(localized: "Recent feeds started on (newest first)")) {
                        HStack(spacing: NBSpacing.s) {
                            ForEach(Array(tracker.recentStartingSides.enumerated()), id: \.offset) { _, side in
                                SideBadge(side: side, style: .soft)
                            }
                        }
                    }
                }
                if tracker.leftShare != nil {
                    VStack(alignment: .leading, spacing: NBSpacing.xs) {
                        SegmentBar(left: tracker.recentLeft, right: tracker.recentRight)
                        Text("L \(DurationText.short(tracker.recentLeft)) · R \(DurationText.short(tracker.recentRight)) across these feeds")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func labelled(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: NBSpacing.xs) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            content()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Quick stats

private struct QuickStatsCard: View {
    let stats: QuickStats

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                ToolHeader(title: "Quick stats", systemImage: "chart.bar.doc.horizontal")
                Grid(alignment: .leading, horizontalSpacing: NBSpacing.l, verticalSpacing: NBSpacing.s) {
                    GridRow {
                        Text("")
                        Text("Today").font(.subheadline.weight(.semibold))
                        Text("This week").font(.subheadline.weight(.semibold))
                    }
                    row(String(localized: "Feeds"), "\(stats.today.feedCount)", "\(stats.thisWeek.feedCount)")
                    row(String(localized: "Breastfeeding"), DurationText.short(stats.today.breastDuration), DurationText.short(stats.thisWeek.breastDuration))
                    row(String(localized: "Bottles"), FeedText.volume(ml: stats.today.bottleML), FeedText.volume(ml: stats.thisWeek.bottleML))
                    row(
                        String(localized: "Average gap"),
                        stats.today.averageInterval.map(DurationText.short) ?? "–",
                        stats.thisWeek.averageInterval.map(DurationText.short) ?? "–"
                    )
                }
                Text("About \(stats.averageFeedsPerDayThisWeek.formatted(.number.precision(.fractionLength(0...1)))) feeds a day this week")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, _ today: String, _ week: String) -> some View {
        GridRow {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(today).font(.subheadline).monospacedDigit()
            Text(week).font(.subheadline).monospacedDigit()
        }
    }
}

// MARK: - Links

private struct MoreLinks: View {
    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                SettingsView()
            } label: {
                linkRow(String(localized: "Settings"), systemImage: "gearshape", detail: String(localized: "Reminders, units, export"))
            }
            .accessibilityIdentifier("tools.settings")
        }
        .buttonStyle(.plain)
        .nbCardBackground()
    }

    private func linkRow(_ title: String, systemImage: String, detail: String) -> some View {
        HStack(spacing: NBSpacing.m) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(NBColor.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(NBSpacing.l)
        .contentShape(Rectangle())
    }
}

#Preview {
    let container = try! PersistenceController.makeContainer(.inMemory)
    HistoryPreviewData.insert(into: container.mainContext)
    return NavigationStack { ToolsView() }
        .modelContainer(container)
}
