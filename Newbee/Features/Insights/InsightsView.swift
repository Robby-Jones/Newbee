import Charts
import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Feeding trends (docs/UX_SPEC.md §3.8): feeds per day, intervals, breast side balance, bottle
/// volume and a time-of-day heatmap, each with a one-line plain summary that compares with the
/// previous period. Everything follows the range picker.
struct InsightsView: View {
    @State private var range: InsightsRange = .week

    var body: some View {
        // The picker sits in a plain stack rather than a top safe-area inset: an inset over the
        // scroll view covered the large navigation title.
        VStack(spacing: 0) {
            Picker("Range", selection: $range) {
                ForEach(InsightsRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, NBSpacing.l)
            .padding(.vertical, NBSpacing.s)

            // The query depends on the range, so it lives in a child view rebuilt per range.
            InsightsContent(range: range)
                .id(range)
        }
        .background(NBColor.canvas)
        .navigationTitle("Insights")
    }
}

extension InsightsRange {
    /// Picker label: "24 h", "7 d", "14 d", "30 d".
    var title: String {
        switch self {
        case .day: String(localized: "24 h")
        case .week: String(localized: "7 d")
        case .twoWeeks: String(localized: "14 d")
        case .month: String(localized: "30 d")
        }
    }

    /// "the previous 7 days", for summaries.
    var previousPeriod: String {
        switch self {
        case .day: String(localized: "the 24 h before")
        case .week: String(localized: "the previous 7 days")
        case .twoWeeks: String(localized: "the previous 14 days")
        case .month: String(localized: "the previous 30 days")
        }
    }
}

private struct InsightsContent: View {
    let range: InsightsRange

    @Query private var sessions: [FeedingSession]
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?

    init(range: InsightsRange) {
        self.range = range
        let now = Date.now
        // Up to an hour ahead so a feed logged after the view appeared still shows.
        _sessions = Query(FeedingSession.completedFeeds(from: range.earliestNeeded(endingAt: now), to: now.addingTimeInterval(3_600)))
    }

    var body: some View {
        let entries = sessions.compactMap(\.feedEntry)
        TimelineView(.everyMinute) { context in
            // The tick's date is the start of the minute; use the real time so a feed logged
            // since then isn't treated as being in the future and left out.
            let report = InsightsReport(entries: entries, range: range, now: max(context.date, .now))
            let unit = bottleModel?.unit ?? .milliliters
            ScrollView {
                VStack(alignment: .leading, spacing: NBSpacing.l) {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "Insights appear after a couple of days of tracking",
                            systemImage: "chart.bar",
                            description: Text("Log feeds with the timer or a bottle and your patterns show up here.")
                        )
                        .padding(.top, NBSpacing.xl)
                    } else {
                        FeedsCard(report: report)
                        if !report.intervals.isEmpty {
                            IntervalsCard(report: report)
                        }
                        if report.breast.sessionCount > 0 {
                            BreastCard(report: report)
                        }
                        if report.bottle.count > 0 {
                            BottleCard(report: report, unit: unit)
                        }
                        if range != .day, !report.isEmpty {
                            HeatmapCard(report: report)
                        }
                        if report.isSparse {
                            SparseNote()
                        }
                        InsightsFooter(includesEstimated: report.includesEstimated)
                    }
                }
                .padding(NBSpacing.l)
            }
        }
    }
}

// MARK: - Cards

/// Title, a one-line summary, then the chart.
private struct InsightCard<Content: View>: View {
    let title: LocalizedStringKey
    let summary: String
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                VStack(alignment: .leading, spacing: NBSpacing.xs) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
        }
    }
}

/// The disclaimer, once under all the cards rather than on each.
private struct InsightsFooter: View {
    let includesEstimated: Bool

    var body: some View {
        let base = String(localized: "Based on your recorded feeds. Not medical advice.")
        Text(includesEstimated ? base + " " + String(localized: "Includes estimated entries.") : base)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, NBSpacing.s)
    }
}

private struct SparseNote: View {
    var body: some View {
        Label("Insights get more useful after a couple of days of tracking. Here's what there is so far.", systemImage: "sparkles")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(NBSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NBColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: NBRadius.control, style: .continuous))
    }
}

/// 1. Feeds per day (or per hour for 24 h), stacked breast/bottle, with an average line.
private struct FeedsCard: View {
    let report: InsightsReport

    var body: some View {
        let unit: Calendar.Component = report.range == .day ? .hour : .day
        let average = Double(report.entries.count) / Double(max(1, report.buckets.count))
        InsightCard(title: report.range == .day ? "Feeds by hour" : "Feeds per day", summary: summary) {
            Chart {
                ForEach(report.buckets) { bucket in
                    BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Feeds", bucket.breastCount))
                        .foregroundStyle(by: .value("Kind", String(localized: "Breast")))
                    BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Feeds", bucket.bottleCount))
                        .foregroundStyle(by: .value("Kind", String(localized: "Bottle")))
                }
                if report.range != .day {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartForegroundStyleScale([String(localized: "Breast"): NBColor.accent, String(localized: "Bottle"): NBColor.bottleBreastMilk])
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .chartXAxis { dateAxis(for: report.range) }
            .frame(height: 180)
            .accessibilityLabel(summary)
        }
    }

    private var summary: String {
        let feeds = report.feedsPerDay
        if report.range == .day {
            let count = report.entries.count
            let previous = Int(feeds.previous.rounded())
            return String(localized: "\(count) feeds in the last 24 h (\(previous) in the 24 h before).")
        }
        let average = feeds.current.formatted(.number.precision(.fractionLength(1)))
        guard feeds.previous > 0 else {
            return String(localized: "Average \(average) feeds a day.")
        }
        let previous = feeds.previous.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "Average \(average) feeds a day, \(Self.trend(feeds)) \(previous) in \(report.range.previousPeriod).")
    }

    /// "up from" / "down from" / "about the same as".
    static func trend(_ comparison: Comparison) -> String {
        switch comparison.direction {
        case .up: String(localized: "up from")
        case .down: String(localized: "down from")
        case .same: String(localized: "about the same as")
        }
    }
}

/// 2. Intervals: average / shortest / longest, and a scatter by time of day.
private struct IntervalsCard: View {
    let report: InsightsReport

    var body: some View {
        InsightCard(title: "Time between feeds", summary: summary) {
            HStack(alignment: .top, spacing: NBSpacing.l) {
                MiniStat(value: report.averageInterval.map(DurationText.short) ?? "–", label: String(localized: "average"))
                MiniStat(value: report.shortestInterval.map(DurationText.short) ?? "–", label: String(localized: "shortest"))
                MiniStat(value: report.longestInterval.map(DurationText.short) ?? "–", label: String(localized: "longest"))
            }
            Chart(report.intervals) { interval in
                PointMark(
                    x: .value("Time of day", Self.hourOfDay(interval.at)),
                    y: .value("Hours since previous", interval.length / 3_600)
                )
                .foregroundStyle(NBColor.accent.opacity(0.8))
                .symbolSize(30)
            }
            .chartXScale(domain: 0...24)
            .chartXAxis {
                AxisMarks(values: [0.0, 6, 12, 18, 24]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Double.self) { Text(Self.hourLabel(Int(hour))) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text("\(hours.formatted(.number.precision(.fractionLength(0...1)))) h") }
                    }
                }
            }
            .frame(height: 160)
            .accessibilityLabel(summary)
            Text("Each dot is a feed: when it started, and how long after the previous one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        guard let average = report.averageInterval else { return "" }
        return String(localized: "Feeds started about \(DurationText.short(average)) apart on average.")
    }

    static func hourOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// "12 AM", "6 AM", "12 PM" (or "00", "06" in 24-hour locales).
    static func hourLabel(_ hour: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

/// 3. Breastfeeding: average session, average per side, and the L/R split.
private struct BreastCard: View {
    let report: InsightsReport

    var body: some View {
        let breast = report.breast
        InsightCard(title: "Breastfeeding", summary: summary) {
            HStack(alignment: .center, spacing: NBSpacing.l) {
                Chart {
                    SectorMark(angle: .value("Time", breast.totalLeft), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(NBColor.left)
                    SectorMark(angle: .value("Time", breast.totalRight), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(NBColor.right)
                }
                .chartBackground { _ in
                    if let share = breast.leftShare {
                        VStack(spacing: 0) {
                            Text("L \(Int((share * 100).rounded()))%")
                            Text("R \(100 - Int((share * 100).rounded()))%")
                        }
                        .font(.caption.weight(.semibold).monospacedDigit())
                    }
                }
                .frame(width: 110, height: 110)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: NBSpacing.s) {
                    MiniStat(value: breast.averageSession.map(DurationText.short) ?? "–", label: String(localized: "average feed"))
                    HStack(spacing: NBSpacing.l) {
                        sideStat(.left, breast.averageLeft)
                        sideStat(.right, breast.averageRight)
                    }
                    Text("Started on L \(breast.startedLeft)× · R \(breast.startedRight)×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sideStat(_ side: Side, _ value: TimeInterval?) -> some View {
        HStack(spacing: NBSpacing.xs) {
            SideBadge(side: side, style: .soft)
            MiniStat(value: value.map(DurationText.short) ?? "–", label: String(localized: "avg"))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.title), average \(value.map(DurationText.spoken) ?? "none")")
    }

    private var summary: String {
        let breast = report.breast
        let count = breast.sessionCount
        switch breast.favouredSide {
        case .left?:
            return String(localized: "\(count) breastfeeds. Left has had more time lately, so starting on the right may help balance.")
        case .right?:
            return String(localized: "\(count) breastfeeds. Right has had more time lately, so starting on the left may help balance.")
        case nil:
            return String(localized: "\(count) breastfeeds, with time well balanced between sides.")
        }
    }
}

/// 4. Bottle: volume per day split by contents, and the average bottle.
private struct BottleCard: View {
    let report: InsightsReport
    let unit: VolumeUnit

    var body: some View {
        let timeUnit: Calendar.Component = report.range == .day ? .hour : .day
        let bottle = report.bottle
        InsightCard(title: "Bottles", summary: summary) {
            HStack(alignment: .top, spacing: NBSpacing.l) {
                MiniStat(value: FeedText.volume(ml: bottle.totalML, unit: unit), label: String(localized: "total"))
                MiniStat(value: bottle.averageML.map { FeedText.volume(ml: $0, unit: unit) } ?? "–", label: String(localized: "average bottle"))
                MiniStat(value: "\(bottle.count)", label: bottle.count == 1 ? String(localized: "bottle") : String(localized: "bottles"))
            }
            Chart {
                ForEach(report.buckets) { bucket in
                    BarMark(x: .value("Time", bucket.start, unit: timeUnit), y: .value(unit.symbol, unit.fromMilliliters(bucket.breastMilkML)))
                        .foregroundStyle(by: .value("Contents", String(localized: "Breast milk")))
                    BarMark(x: .value("Time", bucket.start, unit: timeUnit), y: .value(unit.symbol, unit.fromMilliliters(bucket.formulaML)))
                        .foregroundStyle(by: .value("Contents", String(localized: "Formula")))
                    BarMark(x: .value("Time", bucket.start, unit: timeUnit), y: .value(unit.symbol, unit.fromMilliliters(bucket.otherML)))
                        .foregroundStyle(by: .value("Contents", String(localized: "Other")))
                }
            }
            .chartForegroundStyleScale([
                String(localized: "Breast milk"): NBColor.bottleBreastMilk,
                String(localized: "Formula"): NBColor.bottleFormula,
                String(localized: "Other"): Color.gray.opacity(0.6),
            ])
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .chartXAxis { dateAxis(for: report.range) }
            .frame(height: 160)
            .accessibilityLabel(summary)
        }
    }

    private var summary: String {
        let bottle = report.bottle
        let perDay = bottle.totalML / max(1, report.interval.duration / 86_400)
        if report.range == .day {
            return String(localized: "\(FeedText.volume(ml: bottle.totalML, unit: unit)) from bottles in the last 24 h.")
        }
        return String(localized: "About \(FeedText.volume(ml: perDay, unit: unit)) a day from bottles.")
    }
}

/// 5. Hour-of-day × day heatmap.
private struct HeatmapCard: View {
    let report: InsightsReport

    var body: some View {
        InsightCard(title: "When feeds happen", summary: summary) {
            let days = Array(Set(report.heatmap.map(\.day))).sorted()
            let maxCount = max(1, report.heatmap.map(\.count).max() ?? 1)
            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                Canvas { context, size in
                    let rows = CGFloat(max(1, days.count))
                    let cellWidth = size.width / 24
                    let cellHeight = size.height / rows
                    let index = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })
                    for cell in report.heatmap {
                        guard let row = index[cell.day] else { continue }
                        let rect = CGRect(x: CGFloat(cell.hour) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
                            .insetBy(dx: 0.75, dy: 0.75)
                        let strength = cell.count == 0 ? 0.06 : 0.25 + 0.75 * Double(cell.count) / Double(maxCount)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(NBColor.accent.opacity(strength)))
                    }
                }
                .frame(height: min(220, CGFloat(days.count) * 10 + 4))
                HStack {
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(IntervalsCard.hourLabel(hour))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text("Each row is a day (oldest at the top), each column an hour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
        }
    }

    private var summary: String {
        var byHour = Array(repeating: 0, count: 24)
        for cell in report.heatmap { byHour[cell.hour] += cell.count }
        // The busiest 3-hour window, wrapping past midnight.
        let windows = (0..<24).map { start in (start, (0..<3).reduce(0) { $0 + byHour[(start + $1) % 24] }) }
        guard let best = windows.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return "" }
        let from = IntervalsCard.hourLabel(best.0)
        let to = IntervalsCard.hourLabel((best.0 + 3) % 24)
        return String(localized: "Busiest stretch: \(from) to \(to).")
    }
}

// MARK: - Shared chart bits

/// Day labels for day ranges, hour labels for 24 h.
private func dateAxis(for range: InsightsRange) -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: range == .day ? 6 : min(range.dayCount, 7))) { _ in
        AxisGridLine()
        AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.day().month(.defaultDigits))
    }
}

#Preview("With feeds") {
    let container = try! PersistenceController.makeContainer(.inMemory)
    HistoryPreviewData.insert(into: container.mainContext)
    return NavigationStack { InsightsView() }
        .modelContainer(container)
        .environment(BottleLogUIModel.preview())
}

#Preview("Empty") {
    NavigationStack { InsightsView() }
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
}
