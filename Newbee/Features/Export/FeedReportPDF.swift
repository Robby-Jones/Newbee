import CoreGraphics
import Foundation
import NewbeeKit
import SwiftUI

/// Draws a `FeedReport` as a US Letter PDF (docs/PRD.md #21): a summary page, then the day-by-day
/// log over as many pages as it needs. Each page is a SwiftUI view drawn with `ImageRenderer`
/// into a PDF context, so the report uses the app's own components and colors (light mode).
@MainActor
enum FeedReportPDF {
    /// Who and what the report is for, shown in its header.
    struct Header {
        /// The baby's name, or empty when no profile is set.
        var babyName: String = ""
        /// "5 wk 2 d old", or `nil` with no birth date.
        var age: String?
        /// The bottle unit setting: bottle totals and every bottle in the log are shown in it.
        var volumeUnit: VolumeUnit = .milliliters
        /// The pumping unit setting, for pumping totals and sessions.
        var pumpVolumeUnit: VolumeUnit = .milliliters
        var generatedAt: Date = .now
    }

    /// US Letter, in points.
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 40
    static var contentWidth: CGFloat { pageSize.width - 2 * margin }
    /// Room for the log's blocks between a page's running header and its footer.
    static let logHeight: CGFloat = pageSize.height - 2 * margin - ReportLayout.headerHeight - ReportLayout.footerHeight

    enum RenderError: LocalizedError {
        case couldNotCreateFile

        var errorDescription: String? {
            String(localized: "The PDF couldn't be created.")
        }
    }

    /// Writes the report to `url` and returns its page count.
    @discardableResult
    static func write(_ report: FeedReport, header: Header, to url: URL, calendar: Calendar = .current) throws -> Int {
        let logPages = paginate(report, header: header, calendar: calendar)
        let pageCount = 1 + logPages.count

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: String(localized: "Feeding report"),
            kCGPDFContextCreator: "Newbee",
        ]
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
            throw RenderError.couldNotCreateFile
        }

        draw(SummaryPage(report: report, header: header, page: 1, pageCount: pageCount, calendar: calendar), header: header, in: context)
        for (index, blocks) in logPages.enumerated() {
            let page = LogPage(report: report, header: header, blocks: blocks, page: index + 2, pageCount: pageCount, calendar: calendar)
            draw(page, header: header, in: context)
        }
        context.closePDF()
        return pageCount
    }

    // MARK: - Pagination

    /// The log as blocks (a day's heading, then one block per feed or pumping session), packed
    /// greedily onto pages by their measured height. A day heading never ends a page alone.
    static func paginate(_ report: FeedReport, header: Header, calendar: Calendar) -> [[LogBlock]] {
        var pages: [[LogBlock]] = []
        var current: [LogBlock] = []
        var used: CGFloat = 0

        func place(_ block: LogBlock, height: CGFloat, keepWith next: CGFloat = 0) {
            if used + height + next > logHeight, !current.isEmpty {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(block)
            used += height
        }

        for day in report.loggedDays {
            let dayHeading = LogBlock.day(day)
            let rows = day.items.map { LogBlock.item($0) }
            let firstRowHeight = rows.first.map { measure($0, header: header, calendar: calendar) } ?? 0
            place(dayHeading, height: measure(dayHeading, header: header, calendar: calendar), keepWith: firstRowHeight)
            for (index, row) in rows.enumerated() {
                place(row, height: index == 0 ? firstRowHeight : measure(row, header: header, calendar: calendar))
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    /// Lines a note may take in the log. Notes have no length limit in the app, and a row taller
    /// than a page would be clipped at the page's foot; 20 lines (about 2,000 characters) fit
    /// with room to spare, and anything longer ends in an ellipsis.
    static let noteLineLimit = 20

    static func measure(_ block: LogBlock, header: Header, calendar: Calendar) -> CGFloat {
        let renderer = ImageRenderer(content: LogBlockView(block: block, calendar: calendar)
            .frame(width: contentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.reportVolumeUnit, header.volumeUnit)
            .environment(\.reportPumpVolumeUnit, header.pumpVolumeUnit)
            .environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        // Rows sit in a VStack with this spacing.
        return ceil(height) + LogPage.rowSpacing
    }

    // MARK: - Drawing

    private static func draw(_ page: some View, header: Header, in context: CGContext) {
        let renderer = ImageRenderer(content: page
            .frame(width: pageSize.width, height: pageSize.height)
            .background(Color.white)
            .environment(\.reportVolumeUnit, header.volumeUnit)
            .environment(\.reportPumpVolumeUnit, header.pumpVolumeUnit)
            .environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(pageSize)
        renderer.render { _, render in
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
        }
    }
}

/// One piece of the log, measured and placed as a unit.
enum LogBlock: Identifiable {
    case day(FeedReport.Day)
    case item(HistoryItem)

    var id: String {
        switch self {
        case .day(let day): "day-\(day.day.timeIntervalSinceReferenceDate)"
        case .item(let item): item.id.uuidString
        }
    }
}

// MARK: - Report text

/// Display text for the report, on top of History's `FeedText`.
enum ReportText {
    /// "Oct 26 – Nov 8, 2026 · 14 days".
    static func range(_ interval: DateInterval, dayCount: Int) -> String {
        let last = interval.end.addingTimeInterval(-1)
        let dates = dayCount <= 1
            ? interval.start.formatted(date: .abbreviated, time: .omitted)
            : (interval.start..<last).formatted(.interval.month(.abbreviated).day().year())
        let days = dayCount == 1 ? String(localized: "1 day") : String(localized: "\(dayCount) days")
        return "\(dates) · \(days)"
    }

    /// "8.4" with at most one decimal.
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// A total in the parent's unit: "540 mL", "18.3 oz".
    static func volume(_ ml: Double, unit: VolumeUnit) -> String {
        FeedText.volume(ml: ml, unit: unit)
    }

    static func gap(_ interval: TimeInterval?) -> String {
        interval.map(DurationText.short) ?? "–"
    }
}
