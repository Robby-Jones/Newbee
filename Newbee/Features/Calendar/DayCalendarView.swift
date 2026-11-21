import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// One day as a simple calendar, like the day view in Outlook or Apple Calendar: the day's totals
/// on top, then an hour grid down the left with each feed and pumping session drawn as a block at
/// its time, as tall as it lasted. Blocks that overlap sit side by side. Tap a block to edit it.
///
/// Used by History's Calendar "Day" tab (with a day switcher as `header`) and by the "Open day"
/// page.
struct DayCalendarPage<Header: View>: View {
    let day: Date
    let header: Header

    @Environment(FeedingSessionUIModel.self) private var model: FeedingSessionUIModel?
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?
    @Query private var sessions: [FeedingSession]
    @Query private var pumpSessions: [FeedingSession]
    /// The breastfeed open in the edit sheet.
    @State private var editing: SessionSnapshot?

    init(day: Date, @ViewBuilder header: () -> Header) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        self.day = start
        self.header = header()
        _sessions = Query(FeedingSession.completedFeeds(from: start, to: end))
        _pumpSessions = Query(FeedingSession.completedPumps(from: start, to: end))
    }

    var body: some View {
        let entries = sessions.compactMap(\.feedEntry)
        let pumps = pumpSessions.compactMap(\.pumpEntry)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                header
                totals(entries: entries, pumps: pumps)
            }
            .padding(.horizontal, NBSpacing.l)
            .padding(.vertical, NBSpacing.s)
            Divider()
            DayHourGrid(
                day: day,
                entries: entries,
                pumps: pumps,
                feedUnit: bottleModel?.unit ?? .milliliters,
                pumpUnit: pumpModel?.unit ?? bottleModel?.unit ?? .milliliters,
                onEdit: edit,
                onEditPump: { pumpModel?.presentEdit(sessionID: $0.id) }
            )
        }
        .background(NBColor.canvas)
        .breastFeedEditSheet($editing)
    }

    /// Feeds · breast · bottle · avg gap | pumping on one row, then the L/R bar. Pumped milk
    /// isn't counted in the feed totals, so a divider keeps it apart.
    @ViewBuilder
    private func totals(entries: [FeedEntry], pumps: [PumpEntry]) -> some View {
        if entries.isEmpty && pumps.isEmpty {
            Text("No feeds on this day")
                .font(.subheadline)
                .foregroundStyle(NBColor.secondaryText)
        } else {
            DayStatsRow(
                totals: entries.isEmpty ? nil : FeedTotals(entries),
                pumps: pumps.isEmpty ? nil : PumpSummary(entries: pumps),
                unit: bottleModel?.unit ?? .milliliters,
                pumpUnit: pumpModel?.unit ?? bottleModel?.unit ?? .milliliters
            )
            let left = entries.reduce(0) { $0 + $1.duration(on: .left) }
            let right = entries.reduce(0) { $0 + $1.duration(on: .right) }
            if left + right > 0 {
                SegmentBar(left: left, right: right, height: 6)
            }
        }
    }

    /// The same edit sheets as History: bottles through the bottle log, breastfeeds here.
    private func edit(_ entry: FeedEntry) {
        if entry.kind == .bottle {
            bottleModel?.presentEdit(sessionID: entry.id)
        } else if model != nil, let session = sessions.first(where: { $0.id == entry.id }) {
            editing = session.sessionSnapshot
        }
    }
}

/// The Day page's totals on one row: the feed stats, a vertical divider after "avg gap", then
/// the pumping total and session count. Falls back to tighter spacing, then to the feed row
/// with the pumping line below it, when the text is too large for one row.
private struct DayStatsRow: View {
    let totals: FeedTotals?
    let pumps: PumpSummary?
    let unit: VolumeUnit
    let pumpUnit: VolumeUnit

    var body: some View {
        ViewThatFits(in: .horizontal) {
            oneRow(spacing: NBSpacing.l)
            oneRow(spacing: NBSpacing.m)
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                if let totals { DayTotalsRow(totals: totals, unit: unit) }
                if let pumps { PumpTotalLine(summary: pumps, unit: pumpUnit) }
            }
        }
    }

    private func oneRow(spacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            if let totals {
                MiniStat(value: "\(totals.feedCount)", label: totals.feedCount == 1 ? String(localized: "feed") : String(localized: "feeds"))
                MiniStat(value: DurationText.short(totals.breastDuration), label: String(localized: "breast"))
                MiniStat(value: FeedText.volume(ml: totals.bottleML, unit: unit), label: String(localized: "bottle"))
                MiniStat(value: totals.averageInterval.map(DurationText.short) ?? "–", label: String(localized: "avg gap"))
            }
            if totals != nil, pumps != nil {
                Divider()
            }
            if let pumps {
                PumpMiniStat(summary: pumps, unit: pumpUnit)
            }
        }
        // Keeps the vertical divider as tall as the stats instead of the whole page.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Pumped total with the session count beneath, in the pumping color like the grid's blocks.
private struct PumpMiniStat: View {
    let summary: PumpSummary
    let unit: VolumeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(FeedText.volume(ml: summary.totalML, unit: unit))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(NBColor.pumpInk)
            HStack(spacing: 3) {
                FeedIcon(.pumping, size: 12)
                Text(summary.count == 1 ? String(localized: "1 pump") : String(localized: "\(summary.count) pumps"))
                    .foregroundStyle(NBColor.secondaryText)
            }
            .font(.caption)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Pumping, \(FeedText.volume(ml: summary.totalML, unit: unit)), \(summary.count == 1 ? String(localized: "1 session") : String(localized: "\(summary.count) sessions"))"))
    }
}

extension DayCalendarPage where Header == EmptyView {
    init(day: Date) {
        self.init(day: day) { EmptyView() }
    }
}

// MARK: - Hour grid

/// A feed or a pumping session placed on the hour grid.
private enum DayBlockItem: Identifiable {
    case feed(FeedEntry)
    case pump(PumpEntry)

    var id: UUID {
        switch self {
        case .feed(let entry): entry.id
        case .pump(let pump): pump.id
        }
    }

    var start: Date {
        switch self {
        case .feed(let entry): entry.start
        case .pump(let pump): pump.startedAt
        }
    }

    var end: Date {
        switch self {
        case .feed(let entry): entry.end ?? entry.start
        case .pump(let pump): pump.endedAt
        }
    }
}

/// 24 hour rows with a label on each hour line and a dashed line at each half hour. Opens
/// scrolled to the day's first feed, or to the current hour today.
private struct DayHourGrid: View {
    let day: Date
    let entries: [FeedEntry]
    let pumps: [PumpEntry]
    let feedUnit: VolumeUnit
    let pumpUnit: VolumeUnit
    let onEdit: (FeedEntry) -> Void
    let onEditPump: (PumpEntry) -> Void

    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 64
    /// Shortest block, so a bottle or a very short feed still has room for its line of text.
    @ScaledMetric(relativeTo: .footnote) private var minimumBlockHeight: CGFloat = 26
    @ScaledMetric(relativeTo: .caption) private var axisWidth: CGFloat = 54
    /// Room above midnight and below the last hour, so their labels aren't cut off.
    private let verticalInset: CGFloat = 10
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        let dayHeight = hourHeight * 24
        ScrollView {
            ZStack(alignment: .topLeading) {
                gridLines
                hourLabels
                blocks(dayHeight: dayHeight)
                if Calendar.current.isDateInToday(day) {
                    nowLine(dayHeight: dayHeight)
                }
            }
            .frame(height: dayHeight)
            .padding(.vertical, verticalInset)
            .padding(.trailing, NBSpacing.s)
        }
        .scrollPosition($position)
        .onAppear {
            // Once laid out: the hour line's label then sits just under the top edge.
            let y = hourHeight * CGFloat(scrollHour)
            DispatchQueue.main.async { position.scrollTo(y: y) }
        }
    }

    /// The hour to open on: an hour before the first feed, the current hour less two today (so
    /// the latest feeds show above it), or 7 AM on an empty day.
    private var scrollHour: Int {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return max(0, calendar.component(.hour, from: .now) - 2)
        }
        let first = (entries.map(\.start) + pumps.map(\.startedAt)).min()
        guard let first else { return 7 }
        return max(0, calendar.component(.hour, from: first) - 1)
    }

    private var gridLines: some View {
        Canvas { context, size in
            let left = axisWidth
            for hour in 0...24 {
                let y = hourHeight * CGFloat(hour)
                var line = Path()
                line.move(to: CGPoint(x: left, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color.secondary.opacity(0.3)), lineWidth: 0.5)
                guard hour < 24 else { continue }
                var half = Path()
                half.move(to: CGPoint(x: left, y: y + hourHeight / 2))
                half.addLine(to: CGPoint(x: size.width, y: y + hourHeight / 2))
                context.stroke(half, with: .color(Color.secondary.opacity(0.18)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            }
        }
        .accessibilityHidden(true)
    }

    /// "9 AM" (or "09" in 24-hour locales) centered on each hour line.
    private var hourLabels: some View {
        ForEach(0...24, id: \.self) { hour in
            Text(Self.hourLabel(hour))
                .font(.caption.monospacedDigit())
                .foregroundStyle(NBColor.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: axisWidth - NBSpacing.s, height: 20, alignment: .trailing)
                .offset(y: hourHeight * CGFloat(hour) - 10)
        }
        .accessibilityHidden(true)
    }

    private func blocks(dayHeight: CGFloat) -> some View {
        let items = entries.map(DayBlockItem.feed) + pumps.map(DayBlockItem.pump)
        let spans = items.map { DayTimelineLayout.span(from: $0.start, to: $0.end, onDay: day) }
        let lanes = DayTimelineLayout.lanes(for: spans, minimumHeight: Double(minimumBlockHeight / dayHeight))
        return GeometryReader { proxy in
            let width = max(0, proxy.size.width - axisWidth - 2)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let span = spans[index]
                let lane = lanes[index]
                let laneWidth = width / CGFloat(max(1, lane.count))
                let height = max(minimumBlockHeight, dayHeight * CGFloat(span.height))
                let top = min(dayHeight * CGFloat(span.top), max(0, dayHeight - height))
                DayBlock(item: item, height: height, feedUnit: feedUnit, pumpUnit: pumpUnit) {
                    switch item {
                    case .feed(let entry): onEdit(entry)
                    case .pump(let pump): onEditPump(pump)
                    }
                }
                .frame(width: max(0, laneWidth - 2), height: height)
                .offset(x: axisWidth + 2 + laneWidth * CGFloat(lane.index), y: top)
            }
        }
    }

    /// A red line across the grid at the current time, like a calendar app's.
    private func nowLine(dayHeight: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            let y = dayHeight * CGFloat(DayTimelineLayout.position(of: context.date, onDay: day))
            HStack(spacing: 0) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Rectangle().fill(Color.red).frame(height: 1)
            }
            .padding(.leading, axisWidth - 3.5)
            .offset(y: y - 3.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func hourLabel(_ hour: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

/// One block on the grid: a soft fill with a solid bar down the left, the icon, the kind in bold
/// and its details on one line, plus the time range when there's room. A breastfeed's fill and
/// bar are split by side (first side on top), like the Week grid.
private struct DayBlock: View {
    let item: DayBlockItem
    let height: CGFloat
    let feedUnit: VolumeUnit
    let pumpUnit: VolumeUnit
    let action: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var twoLineHeight: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: action) {
            HStack(alignment: .top, spacing: 6) {
                FeedIcon(glyph, size: 16)
                    .foregroundStyle(ink)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(kind)
                            .font(.footnote.weight(.semibold))
                            .layoutPriority(1)
                        Text(detail)
                            .font(.footnote.monospacedDigit())
                    }
                    .lineLimit(1)
                    if height >= twoLineHeight {
                        Text(timeRange)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(NBColor.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if hasNotes {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(NBColor.secondaryText)
                }
            }
            .foregroundStyle(.primary)
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { fills(opacity: 0.3).background(NBColor.card) }
            .overlay(alignment: .leading) { fills(opacity: 1).frame(width: 4) }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(Text("Opens it to edit"))
        .accessibilityIdentifier("calendar.day.block")
    }

    /// The block's colors from top to bottom, each with its share of the height.
    private var parts: [(color: Color, weight: Double)] {
        switch item {
        case .pump:
            return [(NBColor.pump, 1)]
        case .feed(let entry):
            switch entry.details {
            case .breast(let left, let right, let firstSide, _):
                let first = firstSide ?? .left
                let sides = [first, first.opposite]
                    .map { (color: NBColor.side($0), weight: $0 == .left ? left : right) }
                    .filter { $0.weight > 0 }
                // A feed with no time on either side still shows when it happened.
                return sides.isEmpty ? [(NBColor.side(first), 1)] : sides
            case .bottle:
                return [(entry.tint, 1)]
            }
        }
    }

    private func fills(opacity: Double) -> some View {
        let parts = parts
        let total = parts.reduce(0) { $0 + $1.weight }
        return GeometryReader { proxy in
            VStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.color.opacity(opacity))
                        .frame(height: proxy.size.height * CGFloat(part.weight / max(total, 1e-9)))
                }
            }
        }
    }

    private var glyph: FeedGlyph {
        switch item {
        case .feed(let entry): entry.glyph
        case .pump: .pumping
        }
    }

    private var ink: Color {
        switch item {
        case .feed(let entry): entry.ink
        case .pump: NBColor.pumpInk
        }
    }

    private var kind: String {
        switch item {
        case .feed(let entry): entry.kind == .bottle ? String(localized: "Bottle") : String(localized: "Breast")
        case .pump: String(localized: "Pumping")
        }
    }

    /// "L 12 min · R 8 min", "120 mL formula" or "120 mL".
    private var detail: String {
        switch item {
        case .feed(let entry):
            switch entry.details {
            case .breast(let left, let right, _, _):
                return FeedText.usedSides(left: left, right: right)
            case .bottle(let bottle):
                return "\(FeedText.volume(ml: bottle.amountML, unit: feedUnit)) \(FeedText.contents(bottle.contents))"
            }
        case .pump(let pump):
            return pump.totalAmount(in: pumpUnit).formatted
        }
    }

    private var hasNotes: Bool {
        switch item {
        case .feed(let entry): !entry.notes.isEmpty
        case .pump(let pump): !pump.notes.isEmpty
        }
    }

    /// "9:05 – 9:27 AM", or just "9:05 AM" for a bottle.
    private var timeRange: String {
        let start = item.start
        let end = item.end
        guard end.timeIntervalSince(start) >= 60 else {
            return start.formatted(date: .omitted, time: .shortened)
        }
        return (start..<end).formatted(.interval.hour().minute())
    }

    private var accessibilityText: String {
        switch item {
        case .feed(let entry):
            var parts = [FeedText.title(entry, unit: feedUnit)]
            if let sides = FeedText.sides(entry) { parts.append(sides) }
            parts.append(timeRange)
            if entry.needsReview { parts.append(String(localized: "Needs review")) }
            if !entry.notes.isEmpty { parts.append(entry.notes) }
            return parts.joined(separator: ", ")
        case .pump(let pump):
            var parts = [PumpText.title(pump, unit: pumpUnit), PumpText.detail(pump, unit: pumpUnit), timeRange]
            if !pump.notes.isEmpty { parts.append(pump.notes) }
            return parts.joined(separator: ", ")
        }
    }
}

#Preview("Day") {
    let container = try! PersistenceController.makeContainer(.inMemory)
    HistoryPreviewData.insert(into: container.mainContext)
    return NavigationStack { DayCalendarPage(day: .now) }
        .modelContainer(container)
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
        .environment(BottleLogUIModel.preview())
        .environment(PumpLogUIModel.preview())
}
