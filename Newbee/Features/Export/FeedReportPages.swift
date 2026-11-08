import Charts
import NewbeeKit
import NewbeeShared
import SwiftUI

// The PDF report's pages. Sizes are in points on a US Letter page, so fonts are fixed sizes
// rather than Dynamic Type: the printout should look the same on every phone.

private enum ReportFont {
    static let title = Font.system(size: 22, weight: .bold, design: .rounded)
    static let heading = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 10)
    static let bodyBold = Font.system(size: 10, weight: .semibold)
    static let small = Font.system(size: 8.5)
    static let caption = Font.system(size: 8, weight: .semibold)
    static let statValue = Font.system(size: 18, weight: .bold, design: .rounded)
}

private let ink = Color(white: 0.12)
private let cardFill = Color(red: 0.98, green: 0.973, blue: 0.961) // NBColor.canvas, light
private let rule = Color(white: 0.88)

/// Running header and footer around every page.
/// Fixed heights of the running header and footer, which pagination subtracts from the page.
enum ReportLayout {
    static let headerHeight: CGFloat = 30
    static let footerHeight: CGFloat = 26
}

struct ReportPageChrome<Content: View>: View {

    let header: FeedReportPDF.Header
    let rangeText: String
    let page: Int
    let pageCount: Int
    /// The first page has its own large header instead of the running one.
    var showsRunningHeader = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsRunningHeader {
                HStack(alignment: .firstTextBaseline) {
                    Text(header.babyName.isEmpty ? String(localized: "Feeding log") : String(localized: "Feeding log · \(header.babyName)"))
                        .font(ReportFont.bodyBold)
                    Spacer()
                    Text(rangeText)
                        .font(ReportFont.small)
                        .foregroundStyle(NBColor.secondaryText)
                }
                .frame(height: ReportLayout.headerHeight - 8, alignment: .top)
                Rectangle().fill(rule).frame(height: 1)
                Spacer().frame(height: 7)
            }
            content
            Spacer(minLength: 0)
            Rectangle().fill(rule).frame(height: 1)
            HStack {
                Text("Logged by parents in Newbee. For reference only, not medical advice.")
                Spacer()
                Text("Created \(header.generatedAt.formatted(date: .abbreviated, time: .shortened)) · Page \(page) of \(pageCount)")
            }
            .font(ReportFont.small)
            .foregroundStyle(NBColor.secondaryText)
            .frame(height: ReportLayout.footerHeight - 1, alignment: .bottom)
        }
        .foregroundStyle(ink)
        .padding(FeedReportPDF.margin)
    }
}

// MARK: - Summary page

struct SummaryPage: View {
    let report: FeedReport
    let header: FeedReportPDF.Header
    let page: Int
    let pageCount: Int
    let calendar: Calendar

    private var unit: VolumeUnit { header.volumeUnit }
    private var rangeText: String { ReportText.range(report.interval, dayCount: report.dayCount) }

    var body: some View {
        ReportPageChrome(header: header, rangeText: rangeText, page: page, pageCount: pageCount, showsRunningHeader: false) {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                if report.isEmpty {
                    Text("Nothing was logged in this range.")
                        .font(ReportFont.heading)
                        .foregroundStyle(NBColor.secondaryText)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    stats
                    ReportCard(title: String(localized: "Day by day")) {
                        DailyCharts(report: report, unit: unit, calendar: calendar)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        breastCard
                        bottleCard
                        pumpCard
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 20))
                .foregroundStyle(NBColor.accent)
                .frame(width: 40, height: 40)
                .background(NBColor.accent.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text("Feeding report")
                    .font(ReportFont.title)
                Text(subtitle)
                    .font(ReportFont.body)
                    .foregroundStyle(NBColor.secondaryText)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !header.babyName.isEmpty { parts.append(header.babyName) }
        if let age = header.age { parts.append(age) }
        parts.append(rangeText)
        return parts.joined(separator: " · ")
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatTile(value: ReportText.decimal(report.feedsPerDay), label: String(localized: "Feeds per day"),
                     detail: String(localized: "\(report.feedCount) feeds in total"))
            StatTile(value: ReportText.gap(report.averageGap), label: String(localized: "Average time between feeds"),
                     detail: String(localized: "Start to start"))
            StatTile(value: ReportText.gap(report.longestGap), label: String(localized: "Longest stretch"),
                     detail: String(localized: "Between two feeds"))
            StatTile(value: ReportText.volume(report.bottleMLPerDay, unit: unit), label: String(localized: "Bottle per day"),
                     detail: String(localized: "\(report.bottle.count) bottles in total"))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var breastCard: some View {
        let breast = report.breast
        return ReportCard(title: String(localized: "Breastfeeding"), symbol: "heart.fill", tint: NBColor.leftInk) {
            FactRow(label: String(localized: "Feeds"), value: "\(breast.count)")
            FactRow(label: String(localized: "Total time"), value: DurationText.short(breast.total))
            FactRow(label: String(localized: "Per day"), value: DurationText.short(report.breastDurationPerDay))
            FactRow(label: String(localized: "Average feed"), value: breast.averageFeed.map(DurationText.short) ?? "–")
            if breast.total > 0 {
                SegmentBar(left: breast.totalLeft, right: breast.totalRight, height: 6)
                    .frame(height: 6)
                    .padding(.top, 2)
                HStack {
                    Text("L \(DurationText.short(breast.totalLeft))")
                        .foregroundStyle(NBColor.leftInk)
                    Spacer()
                    Text("R \(DurationText.short(breast.totalRight))")
                        .foregroundStyle(NBColor.rightInk)
                }
                .font(ReportFont.small.weight(.semibold))
            }
            FactRow(label: String(localized: "Started on L / R"), value: "\(breast.startedLeft) / \(breast.startedRight)")
        }
    }

    private var bottleCard: some View {
        let bottle = report.bottle
        return ReportCard(title: String(localized: "Bottles"), symbol: "waterbottle.fill", tint: NBColor.bottleBreastMilkInk) {
            FactRow(label: String(localized: "Bottles"), value: "\(bottle.count)")
            FactRow(label: String(localized: "Total"), value: ReportText.volume(bottle.totalML, unit: unit))
            FactRow(label: String(localized: "Average bottle"), value: bottle.averageML.map { ReportText.volume($0, unit: unit) } ?? "–")
            FactRow(label: String(localized: "Breast milk"), value: ReportText.volume(bottle.breastMilkML, unit: unit))
            FactRow(label: String(localized: "Formula"), value: ReportText.volume(bottle.formulaML, unit: unit))
            if bottle.otherML > 0 {
                FactRow(label: String(localized: "Other"), value: ReportText.volume(bottle.otherML, unit: unit))
            }
        }
    }

    private var pumpCard: some View {
        let pump = report.pump
        return ReportCard(title: String(localized: "Pumping"), symbol: "drop.fill", tint: NBColor.pumpInk) {
            FactRow(label: String(localized: "Sessions"), value: "\(pump.count)")
            FactRow(label: String(localized: "Total"), value: ReportText.volume(pump.totalML, unit: unit))
            FactRow(label: String(localized: "Per day"), value: ReportText.volume(report.pumpMLPerDay, unit: unit))
            FactRow(label: String(localized: "Left"), value: ReportText.volume(pump.leftML, unit: unit))
            FactRow(label: String(localized: "Right"), value: ReportText.volume(pump.rightML, unit: unit))
        }
    }
}

/// Feeds per day (breast and bottle stacked) above bottle volume per day, on one date axis.
private struct DailyCharts: View {
    let report: FeedReport
    let unit: VolumeUnit
    let calendar: Calendar

    /// Label every day for a week, then thin the labels so about seven fit.
    private var labelStride: Int { max(1, Int((Double(report.dayCount) / 7).rounded(.up))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            Text("Feeds per day").font(ReportFont.caption).foregroundStyle(NBColor.secondaryText)
            Chart(report.days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.breastCount))
                    .foregroundStyle(NBColor.left)
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.bottleCount))
                    .foregroundStyle(NBColor.bottleBreastMilk)
            }
            .chartXAxis { dayAxis }
            .chartYAxis { valueAxis }
            .frame(height: 110)

            Text("Bottle volume per day (\(unit.symbol))").font(ReportFont.caption).foregroundStyle(NBColor.secondaryText)
            Chart(report.days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value(unit.symbol, unit.fromMilliliters(day.bottleML)))
                    .foregroundStyle(NBColor.bottleFormula)
            }
            .chartXAxis { dayAxis }
            .chartYAxis { valueAxis }
            .frame(height: 80)
        }
    }

    private var valueAxis: some AxisContent {
        AxisMarks(position: .leading) { _ in
            AxisGridLine()
            AxisValueLabel()
                .font(ReportFont.small)
        }
    }

    private var dayAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: labelStride)) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                .font(ReportFont.small)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendDot(color: NBColor.left, text: String(localized: "Breastfeeds"))
            LegendDot(color: NBColor.bottleBreastMilk, text: String(localized: "Bottles"))
            LegendDot(color: NBColor.bottleFormula, text: String(localized: "Bottle volume"))
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(ReportFont.small).foregroundStyle(NBColor.secondaryText)
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ReportFont.statValue)
                .foregroundStyle(NBColor.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(ReportFont.caption)
            Text(detail).font(ReportFont.small).foregroundStyle(NBColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(NBColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ReportCard<Content: View>: View {
    let title: String
    var symbol: String?
    var tint: Color = NBColor.accent
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(tint)
                }
                Text(title).font(ReportFont.heading)
            }
            .padding(.bottom, 2)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(rule, lineWidth: 0.5))
    }
}

private struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(NBColor.secondaryText)
            Spacer(minLength: 4)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(ReportFont.body)
    }
}

// MARK: - Log pages

struct LogPage: View {
    static let rowSpacing: CGFloat = 4

    let report: FeedReport
    let header: FeedReportPDF.Header
    let blocks: [LogBlock]
    let page: Int
    let pageCount: Int
    let calendar: Calendar

    var body: some View {
        ReportPageChrome(header: header, rangeText: ReportText.range(report.interval, dayCount: report.dayCount),
                         page: page, pageCount: pageCount) {
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(blocks) { block in
                    LogBlockView(block: block, calendar: calendar)
                        .frame(width: FeedReportPDF.contentWidth)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A day heading with that day's totals, or one feed or pumping session.
struct LogBlockView: View {
    let block: LogBlock
    let calendar: Calendar

    var body: some View {
        switch block {
        case .day(let day): DayHeading(day: day)
        case .item(let item): LogRow(item: item)
        }
    }
}

private struct DayHeading: View {
    let day: FeedReport.Day

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(ReportFont.heading)
            Spacer()
            Text(totals)
                .font(ReportFont.small)
                .foregroundStyle(NBColor.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(NBColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.top, 8)
    }

    /// "9 feeds · Breast 2 h 10 min · Bottle 240 mL · Pumped 180 mL".
    private var totals: String {
        var parts = [day.feedCount == 1 ? String(localized: "1 feed") : String(localized: "\(day.feedCount) feeds")]
        if day.breastCount > 0 { parts.append(String(localized: "Breast \(DurationText.short(day.breastDuration))")) }
        if day.bottleCount > 0 { parts.append(String(localized: "Bottle \(FeedText.volume(ml: day.bottleML, unit: unit))")) }
        if day.pumpCount > 0 { parts.append(String(localized: "Pumped \(FeedText.volume(ml: day.pumpML, unit: unit))")) }
        return parts.joined(separator: " · ")
    }

    @Environment(\.reportVolumeUnit) private var unit
}

private struct LogRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.start.formatted(date: .omitted, time: .shortened))
                .font(ReportFont.body.monospacedDigit())
                .foregroundStyle(NBColor.secondaryText)
                .frame(width: 52, alignment: .leading)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(ReportFont.bodyBold)
                    if let detail {
                        Text(detail).font(ReportFont.body).foregroundStyle(NBColor.secondaryText)
                    }
                    if needsReview {
                        Text("Times estimated").font(ReportFont.caption).foregroundStyle(NBColor.reviewInk)
                    }
                    Spacer(minLength: 0)
                    if let gap {
                        Text("\(DurationText.short(gap)) after the previous feed")
                            .font(ReportFont.small)
                            .foregroundStyle(NBColor.secondaryText)
                    }
                }
                if !notes.isEmpty {
                    Text(notes)
                        .font(ReportFont.small.italic())
                        .foregroundStyle(NBColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch item {
        case .feed(let row): row.entry.tint
        case .pump: NBColor.pump
        }
    }

    private var title: String {
        switch item {
        case .feed(let row): FeedText.title(row.entry)
        case .pump(let entry): PumpText.title(entry)
        }
    }

    private var detail: String? {
        switch item {
        case .feed(let row): FeedText.sides(row.entry)
        case .pump(let entry): PumpText.detail(entry)
        }
    }

    private var notes: String {
        switch item {
        case .feed(let row): row.entry.notes
        case .pump(let entry): entry.notes
        }
    }

    private var needsReview: Bool {
        if case .feed(let row) = item { return row.entry.needsReview }
        return false
    }

    private var gap: TimeInterval? {
        if case .feed(let row) = item { return row.sincePrevious }
        return nil
    }
}

// MARK: - Environment

private struct ReportVolumeUnitKey: EnvironmentKey {
    static let defaultValue: VolumeUnit = .milliliters
}

extension EnvironmentValues {
    /// The unit for day totals in the report log.
    var reportVolumeUnit: VolumeUnit {
        get { self[ReportVolumeUnitKey.self] }
        set { self[ReportVolumeUnitKey.self] = newValue }
    }
}
