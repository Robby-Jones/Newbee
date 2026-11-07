import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Monthly feeding calendar (docs/UX_SPEC.md §3.5): a month grid with side and bottle dots,
/// shaded by how busy each day was, and the selected day's summary underneath.
///
/// Shown as History's Calendar mode; `HistoryView` owns the title and the `DayRoute` destination.
struct CalendarView: View {
    @State private var month: Date = FeedCalendar.startOfMonth(.now)
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: .now)

    var body: some View {
        // The month's query lives in a child view so it's rebuilt for each month.
        CalendarMonthView(month: month, selectedDay: $selectedDay, changeMonth: changeMonth(by:), showDay: show(day:))
            .id(month)
            .background(NBColor.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        month = FeedCalendar.startOfMonth(.now)
                        selectedDay = Calendar.current.startOfDay(for: .now)
                    }
                    .disabled(month == FeedCalendar.startOfMonth(.now) && selectedDay == Calendar.current.startOfDay(for: .now))
                }
            }
    }

    private func changeMonth(by offset: Int) {
        let next = FeedCalendar.month(byAdding: offset, to: month)
        // Never page past the current month: there's nothing to show there.
        guard next <= FeedCalendar.startOfMonth(.now) else { return }
        month = next
        selectedDay = nil
    }

    /// Jumps to `day`'s month and selects it (tapping a padding day from a neighbouring month).
    private func show(day: Date) {
        guard day <= .now else { return }
        month = FeedCalendar.startOfMonth(day)
        selectedDay = Calendar.current.startOfDay(for: day)
    }
}

/// Pushes the full day timeline.
struct DayRoute: Hashable {
    let day: Date
}

private struct CalendarMonthView: View {
    let month: Date
    @Binding var selectedDay: Date?
    let changeMonth: (Int) -> Void
    let showDay: (Date) -> Void

    @Query private var sessions: [FeedingSession]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?

    init(month: Date, selectedDay: Binding<Date?>, changeMonth: @escaping (Int) -> Void, showDay: @escaping (Date) -> Void) {
        self.month = month
        _selectedDay = selectedDay
        self.changeMonth = changeMonth
        self.showDay = showDay
        // The month plus a week either side, for the padding days in the grid.
        let interval = FeedCalendar.monthInterval(containing: month)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
        let end = calendar.date(byAdding: .day, value: 7, to: interval.end) ?? interval.end
        _sessions = Query(FeedingSession.completedFeeds(from: start, to: end))
    }

    var body: some View {
        let entries = sessions.compactMap(\.feedEntry)
        let now = Date.now
        let grid = FeedCalendar.month(month, entries: entries, now: now)
        let isCurrentMonth = month == FeedCalendar.startOfMonth(now)

        ScrollView {
            VStack(alignment: .leading, spacing: NBSpacing.l) {
                Card(padding: NBSpacing.m) {
                    VStack(spacing: NBSpacing.m) {
                        monthHeader(isCurrentMonth: isCurrentMonth)
                        MonthGrid(grid: grid, selectedDay: selectedDay) { cell in
                            select(cell)
                        }
                        .opacity(grid.isEmpty ? 0.6 : 1)
                        .gesture(swipe(isCurrentMonth: isCurrentMonth))
                        legend
                    }
                }

                if let selectedDay {
                    let summary = FeedCalendar.daySummary(selectedDay, entries: entries)
                    DaySummaryCard(day: selectedDay, entries: summary.entries, totals: summary.totals, unit: bottleModel?.unit ?? .milliliters)
                } else if grid.isEmpty {
                    Text("No feeds this month")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, NBSpacing.l)
                } else {
                    MonthSummary(totals: grid.totals, unit: bottleModel?.unit ?? .milliliters)
                }
            }
            .padding(NBSpacing.l)
        }
    }

    private func monthHeader(isCurrentMonth: Bool) -> some View {
        HStack {
            Button {
                changeMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: NBLayout.minHitTarget, height: NBLayout.minHitTarget)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(month, format: .dateTime.month(.wide).year())
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                changeMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: NBLayout.minHitTarget, height: NBLayout.minHitTarget)
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
        .font(.body.weight(.semibold))
    }

    private var legend: some View {
        HStack(spacing: NBSpacing.l) {
            LegendDot(color: NBColor.left, label: "Left")
            LegendDot(color: NBColor.right, label: "Right")
            LegendDot(color: NBColor.bottleBreastMilk, label: "Bottle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func select(_ cell: CalendarDayCell) {
        guard !cell.isFuture else { return }
        if !cell.isInMonth {
            showDay(cell.day)
            return
        }
        withAnimation(reduceMotion ? nil : .nbState) {
            selectedDay = selectedDay == cell.day ? nil : cell.day
        }
    }

    private func swipe(isCurrentMonth: Bool) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height), abs(dx) > 60 else { return }
                if dx < 0, !isCurrentMonth { changeMonth(1) }
                if dx > 0 { changeMonth(-1) }
            }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: NBSpacing.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}

/// Seven columns of day cells under the weekday initials.
private struct MonthGrid: View {
    let grid: CalendarMonth
    let selectedDay: Date?
    let onSelect: (CalendarDayCell) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(Self.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            ForEach(grid.weeks.flatMap { $0 }) { cell in
                Button {
                    onSelect(cell)
                } label: {
                    DayCell(cell: cell, isSelected: cell.day == selectedDay)
                }
                .buttonStyle(.plain)
                .disabled(cell.isFuture)
            }
        }
    }

    /// Very short weekday names, starting on the locale's first weekday.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

private struct DayCell: View {
    let cell: CalendarDayCell
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 3) {
            Text("\(cell.dayNumber)")
                .font(.callout.weight(cell.isToday ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            HStack(spacing: 2) {
                if cell.usedLeft { dot(NBColor.left) }
                if cell.usedRight { dot(NBColor.right) }
                if cell.hadBottle { dot(NBColor.bottleBreastMilk) }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
        .background {
            if isSelected {
                shape.fill(NBColor.accent)
            } else {
                shape.fill(NBColor.accent.opacity(Double(cell.intensity) * 0.07))
            }
        }
        .overlay {
            if cell.isToday && !isSelected {
                shape.strokeBorder(NBColor.accent, lineWidth: 1.5)
            }
        }
        .opacity(cell.isInMonth ? (cell.isFuture ? 0.35 : 1) : 0.3)
        .contentShape(shape)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .overlay { if isSelected { Circle().strokeBorder(.white, lineWidth: 0.5) } }
    }

    private var accessibilityText: String {
        let date = cell.day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        var parts = [date]
        if cell.isToday { parts.append(String(localized: "today")) }
        switch cell.feedCount {
        case 0: parts.append(String(localized: "no feeds"))
        case 1: parts.append(String(localized: "1 feed"))
        default: parts.append(String(localized: "\(cell.feedCount) feeds"))
        }
        if cell.hadBottle { parts.append(String(localized: "includes a bottle")) }
        return parts.joined(separator: ", ")
    }
}

/// The selected day: totals, the L/R split, its feeds, and a link to the full day.
private struct DaySummaryCard: View {
    let day: Date
    let entries: [FeedEntry]
    let totals: FeedTotals
    let unit: VolumeUnit

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                Text(FeedText.dayTitle(day))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if entries.isEmpty {
                    Text("No feeds recorded on this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    DayTotalsRow(totals: totals, unit: unit)
                    let left = entries.reduce(0) { $0 + $1.duration(on: .left) }
                    let right = entries.reduce(0) { $0 + $1.duration(on: .right) }
                    if left + right > 0 {
                        VStack(alignment: .leading, spacing: NBSpacing.xs) {
                            SegmentBar(left: left, right: right)
                            Text("L \(DurationText.short(left)) · R \(DurationText.short(right))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    let rows = FeedTimeline.days(from: entries).first?.rows ?? []
                    ForEach(rows.prefix(6)) { row in
                        FeedRow(row: row)
                    }
                    if rows.count > 6 {
                        Text("and \(rows.count - 6) more")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink(value: DayRoute(day: day)) {
                        Label("Open day", systemImage: "list.bullet")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(NBColor.accent)
                    .accessibilityIdentifier("calendar.openDay")
                }
            }
        }
    }
}

/// Feeds · breastfeeding · bottles · average gap.
struct DayTotalsRow: View {
    let totals: FeedTotals
    let unit: VolumeUnit

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: NBSpacing.l) { stats }
            VStack(alignment: .leading, spacing: NBSpacing.s) { stats }
        }
    }

    @ViewBuilder
    private var stats: some View {
        MiniStat(value: "\(totals.feedCount)", label: totals.feedCount == 1 ? String(localized: "feed") : String(localized: "feeds"))
        MiniStat(value: DurationText.short(totals.breastDuration), label: String(localized: "breast"))
        MiniStat(value: FeedText.volume(ml: totals.bottleML, unit: unit), label: String(localized: "bottle"))
        MiniStat(value: totals.averageInterval.map(DurationText.short) ?? "–", label: String(localized: "avg gap"))
    }
}

/// A small number over a caption.
struct MiniStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown when no day is selected: the month's totals.
private struct MonthSummary: View {
    let totals: FeedTotals
    let unit: VolumeUnit

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                Text("This month")
                    .font(.title3.weight(.semibold))
                DayTotalsRow(totals: totals, unit: unit)
                Text("Tap a day to see its feeds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("With feeds") {
    let container = try! PersistenceController.makeContainer(.inMemory)
    HistoryPreviewData.insert(into: container.mainContext)
    return NavigationStack { CalendarView().navigationDestination(for: DayRoute.self) { DayFeedsView(day: $0.day) } }
        .modelContainer(container)
        .environment(BottleLogUIModel.preview())
}

#Preview("Empty") {
    NavigationStack { CalendarView() }
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
}
