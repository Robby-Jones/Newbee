import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Feeding calendar (docs/UX_SPEC.md §3.5), History's Calendar mode.
///
/// **Week** (the default) lays the week out as seven day columns on a 24-hour axis, each feed a
/// block at its time, like the calendars in popular baby trackers: rhythms and gaps show at a
/// glance. **Month** is the grid with side, bottle and pumping dots, shaded by how busy each day
/// was. Pumping shows in both but never counts as a feed. Either way the selected day's summary
/// sits underneath.
///
/// `HistoryView` owns the title, the `DayRoute` destination, and the selected day.
struct CalendarView: View {
    enum Scope: Hashable {
        case week, month
    }

    @State private var scope: Scope = .week
    @State private var month: Date
    @State private var weekStart: Date
    /// Owned by `HistoryView` so its Add menu can default new entries to this day.
    @Binding var selectedDay: Date?

    init(selectedDay: Binding<Date?>) {
        _selectedDay = selectedDay
        let anchor = selectedDay.wrappedValue ?? .now
        _month = State(initialValue: FeedCalendar.startOfMonth(anchor))
        _weekStart = State(initialValue: CalendarView.startOfWeek(containing: anchor))
    }

    var body: some View {
        // Each period's query lives in a child view so it's rebuilt when the period changes.
        Group {
            switch scope {
            case .week:
                CalendarWeekView(weekStart: weekStart, selectedDay: $selectedDay, scope: $scope, changeWeek: changeWeek(by:))
                    .id(weekStart)
            case .month:
                CalendarMonthView(month: month, selectedDay: $selectedDay, scope: $scope, changeMonth: changeMonth(by:), showDay: show(day:))
                    .id(month)
            }
        }
        .background(NBColor.canvas)
        .onChange(of: scope) { _, _ in
            // Keep the same period in view when switching between week and month.
            let anchor = selectedDay ?? (scope == .month ? weekStart : month)
            month = FeedCalendar.startOfMonth(anchor)
            weekStart = Self.startOfWeek(containing: anchor)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") {
                    month = FeedCalendar.startOfMonth(.now)
                    weekStart = Self.startOfWeek(containing: .now)
                    selectedDay = Calendar.current.startOfDay(for: .now)
                }
                .disabled(isShowingToday)
            }
        }
    }

    private var isShowingToday: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        let periodIsCurrent = scope == .week
            ? weekStart == Self.startOfWeek(containing: .now)
            : month == FeedCalendar.startOfMonth(.now)
        return periodIsCurrent && selectedDay == today
    }

    /// The first day of the locale's week containing `date`.
    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func changeWeek(by offset: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: 7 * offset, to: weekStart) else { return }
        // Never page past the current week: there's nothing to show there.
        guard next <= Self.startOfWeek(containing: .now) else { return }
        weekStart = next
        selectedDay = nil
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

/// Week | Month.
private struct ScopePicker: View {
    @Binding var scope: CalendarView.Scope

    var body: some View {
        Picker("Calendar view", selection: $scope) {
            Text("Week").tag(CalendarView.Scope.week)
            Text("Month").tag(CalendarView.Scope.month)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// Left, Right, Bottle, Pumping color key.
private struct CalendarLegend: View {
    var body: some View {
        HStack(spacing: NBSpacing.l) {
            LegendDot(color: NBColor.left, label: "Left")
            LegendDot(color: NBColor.right, label: "Right")
            LegendDot(color: NBColor.bottleBreastMilk, label: "Bottle")
            LegendDot(color: NBColor.pump, label: "Pumping")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Week

private struct CalendarWeekView: View {
    let weekStart: Date
    @Binding var selectedDay: Date?
    @Binding var scope: CalendarView.Scope
    let changeWeek: (Int) -> Void

    @Query private var sessions: [FeedingSession]
    @Query private var pumpSessions: [FeedingSession]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?

    init(weekStart: Date, selectedDay: Binding<Date?>, scope: Binding<CalendarView.Scope>, changeWeek: @escaping (Int) -> Void) {
        self.weekStart = weekStart
        _selectedDay = selectedDay
        _scope = scope
        self.changeWeek = changeWeek
        let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
        _sessions = Query(FeedingSession.completedFeeds(from: weekStart, to: end))
        _pumpSessions = Query(FeedingSession.completedPumps(from: weekStart, to: end))
    }

    var body: some View {
        let calendar = Calendar.current
        let entries = sessions.compactMap(\.feedEntry)
        let pumps = pumpSessions.compactMap(\.pumpEntry)
        let now = Date.now
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let isCurrentWeek = weekStart == CalendarView.startOfWeek(containing: now)
        let unit = bottleModel?.unit ?? .milliliters
        let pumpUnit = pumpModel?.unit ?? unit

        ScrollView {
            VStack(alignment: .leading, spacing: NBSpacing.l) {
                Card(padding: NBSpacing.m) {
                    VStack(spacing: NBSpacing.m) {
                        header(days: days, isCurrentWeek: isCurrentWeek)
                        WeekTimeline(days: days, entries: entries, pumps: pumps, selectedDay: selectedDay, now: now, onSelect: select)
                            .gesture(swipe(isCurrentWeek: isCurrentWeek))
                        CalendarLegend()
                    }
                }

                if let selectedDay, days.contains(selectedDay) {
                    let summary = FeedCalendar.daySummary(selectedDay, entries: entries)
                    DaySummaryCard(
                        day: selectedDay,
                        entries: summary.entries,
                        totals: summary.totals,
                        pumps: FeedCalendar.dayPumps(selectedDay, pumps: pumps),
                        unit: unit,
                        pumpUnit: pumpUnit
                    )
                } else if entries.isEmpty && pumps.isEmpty {
                    Text("No feeds this week")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, NBSpacing.l)
                } else {
                    PeriodSummary(title: "This week", totals: FeedTotals(entries), pumps: PumpSummary(entries: pumps), unit: unit, pumpUnit: pumpUnit)
                }
            }
            .padding(NBSpacing.l)
        }
    }

    private func header(days: [Date], isCurrentWeek: Bool) -> some View {
        HStack(spacing: NBSpacing.xs) {
            Button {
                changeWeek(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: NBLayout.minHitTarget, height: NBLayout.minHitTarget)
            }
            .accessibilityLabel("Previous week")
            Text(Self.title(days))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Button {
                changeWeek(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: NBLayout.minHitTarget, height: NBLayout.minHitTarget)
            }
            .disabled(isCurrentWeek)
            .accessibilityLabel("Next week")
            Spacer(minLength: NBSpacing.s)
            ScopePicker(scope: $scope)
        }
        .font(.body.weight(.semibold))
    }

    /// "Nov 2 – 8", or "Oct 26 – Nov 1" across a month boundary.
    static func title(_ days: [Date], calendar: Calendar = .current) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let start = first.formatted(.dateTime.month(.abbreviated).day())
        let end = last.formatted(sameMonth ? .dateTime.day() : .dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    private func select(_ day: Date) {
        guard day <= .now else { return }
        withAnimation(reduceMotion ? nil : .nbState) {
            selectedDay = selectedDay == day ? nil : day
        }
    }

    private func swipe(isCurrentWeek: Bool) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height), abs(dx) > 60 else { return }
                if dx < 0, !isCurrentWeek { changeWeek(1) }
                if dx > 0 { changeWeek(-1) }
            }
    }
}

/// Seven day columns on a 24-hour axis. Each feed is a block at its start time, as tall as it
/// lasted: breastfeeds split lavender / teal by side, bottles a small capsule in the bottle's
/// color. Pumping sessions are narrow rose bars along the column's trailing edge, so they never
/// hide a feed. Tap a day's header (or its column) to see that day's feeds.
private struct WeekTimeline: View {
    let days: [Date]
    let entries: [FeedEntry]
    let pumps: [PumpEntry]
    let selectedDay: Date?
    let now: Date
    let onSelect: (Date) -> Void

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 420
    private let axisWidth: CGFloat = 30
    private static let axisHours = Array(stride(from: 0, to: 24, by: 3))

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: NBSpacing.s) {
            HStack(spacing: 0) {
                Color.clear.frame(width: axisWidth, height: 1)
                ForEach(days, id: \.self) { day in
                    dayHeader(
                        day,
                        feedCount: feeds(on: day, calendar: calendar).count,
                        pumpCount: pumps(on: day, calendar: calendar).count,
                        calendar: calendar
                    )
                }
            }

            HStack(alignment: .top, spacing: 0) {
                axis
                ForEach(days, id: \.self) { day in
                    DayColumn(
                        day: day,
                        entries: feeds(on: day, calendar: calendar),
                        pumps: pumps(on: day, calendar: calendar),
                        isSelected: day == selectedDay,
                        height: chartHeight
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(day) }
                    .accessibilityHidden(true)
                }
            }
            .frame(height: chartHeight)
            .background { gridLines }
        }
    }

    private func feeds(on day: Date, calendar: Calendar) -> [FeedEntry] {
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return entries.filter { $0.start >= day && $0.start < end }
    }

    private func pumps(on day: Date, calendar: Calendar) -> [PumpEntry] {
        FeedCalendar.dayPumps(day, pumps: pumps, calendar: calendar)
    }

    private func dayHeader(_ day: Date, feedCount: Int, pumpCount: Int, calendar: Calendar) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = day == selectedDay
        let isFuture = day > now
        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isToday || isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : (isToday ? NBColor.accent : Color.primary))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isSelected ? NBColor.accent : Color.clear))
            }
            .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .opacity(isFuture ? 0.35 : 1)
        .accessibilityLabel(Self.accessibilityText(day, feedCount: feedCount, pumpCount: pumpCount, isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Hour labels every 3 hours down the left edge.
    private var axis: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.axisHours, id: \.self) { hour in
                Text(Self.hourLabel(hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .offset(y: chartHeight * CGFloat(hour) / 24 - 1)
            }
        }
        .frame(width: axisWidth, height: chartHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Faint lines across the columns every 3 hours.
    private var gridLines: some View {
        Canvas { context, size in
            for hour in Self.axisHours + [24] {
                let y = size.height * CGFloat(hour) / 24
                var line = Path()
                line.move(to: CGPoint(x: axisWidth, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color.secondary.opacity(0.18)), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    /// "12a", "3p" (or "00", "15" in 24-hour locales).
    static func hourLabel(_ hour: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow)))
    }

    static func accessibilityText(_ day: Date, feedCount: Int, pumpCount: Int, isToday: Bool) -> String {
        var parts = [day.formatted(.dateTime.weekday(.wide).day().month(.wide))]
        if isToday { parts.append(String(localized: "today")) }
        switch feedCount {
        case 0: parts.append(String(localized: "no feeds"))
        case 1: parts.append(String(localized: "1 feed"))
        default: parts.append(String(localized: "\(feedCount) feeds"))
        }
        if let pumping = PumpCountText.spoken(pumpCount) { parts.append(pumping) }
        return parts.joined(separator: ", ")
    }
}

/// One day's feeds as blocks positioned by time of day, with its pumping sessions on top.
private struct DayColumn: View {
    let day: Date
    let entries: [FeedEntry]
    let pumps: [PumpEntry]
    let isSelected: Bool
    let height: CGFloat

    private static let dayLength: TimeInterval = 24 * 3_600

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? NBColor.accent.opacity(0.08) : Color.clear)
            ForEach(entries) { entry in
                let top = height * CGFloat(max(0, entry.start.timeIntervalSince(day)) / Self.dayLength)
                FeedBlock(entry: entry, height: blockHeight(from: entry.start, to: entry.end ?? entry.start, top: top))
                    .padding(.horizontal, 3)
                    .offset(y: top)
            }
            ForEach(pumps) { pump in
                let top = height * CGFloat(max(0, pump.startedAt.timeIntervalSince(day)) / Self.dayLength)
                PumpBlock(height: blockHeight(from: pump.startedAt, to: pump.endedAt, top: top))
                    .padding(.trailing, 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// As tall as the entry lasted (at least 6 pt so short ones stay visible), clipped at midnight.
    private func blockHeight(from start: Date, to end: Date, top: CGFloat) -> CGFloat {
        let span = end.timeIntervalSince(start)
        let natural = height * CGFloat(span / Self.dayLength)
        return max(6, min(natural, height - top))
    }
}

/// A breastfeed as stacked side segments (first side on top), or a bottle as a capsule.
private struct FeedBlock: View {
    let entry: FeedEntry
    let height: CGFloat

    var body: some View {
        switch entry.details {
        case .breast(let left, let right, let firstSide, _):
            let first = firstSide ?? .left
            let firstTime = first == .left ? left : right
            let secondTime = first == .left ? right : left
            let total = max(firstTime + secondTime, 1)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(NBColor.side(first))
                    .frame(height: height * CGFloat(firstTime / total))
                Rectangle()
                    .fill(NBColor.side(first.opposite))
                    .frame(height: height * CGFloat(secondTime / total))
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .bottle(let bottle):
            Capsule()
                .fill(bottle.contents == .formula ? NBColor.bottleFormula : bottle.contents == .breastMilk ? NBColor.bottleBreastMilk : Color.gray.opacity(0.6))
                .frame(height: max(6, min(height, 8)))
        }
    }
}

/// A pumping session: a narrow rose bar, outlined so it stands out over a feed block.
private struct PumpBlock: View {
    let height: CGFloat

    var body: some View {
        Capsule()
            .fill(NBColor.pump)
            .overlay { Capsule().strokeBorder(NBColor.card, lineWidth: 1) }
            .frame(width: 7, height: max(8, height))
    }
}

/// "1 pumping session" / "3 pumping sessions", for VoiceOver; `nil` for none.
enum PumpCountText {
    static func spoken(_ count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: String(localized: "1 pumping session")
        default: String(localized: "\(count) pumping sessions")
        }
    }
}

/// Pushes the full day timeline.
struct DayRoute: Hashable {
    let day: Date
}

private struct CalendarMonthView: View {
    let month: Date
    @Binding var selectedDay: Date?
    @Binding var scope: CalendarView.Scope
    let changeMonth: (Int) -> Void
    let showDay: (Date) -> Void

    @Query private var sessions: [FeedingSession]
    @Query private var pumpSessions: [FeedingSession]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?

    init(
        month: Date,
        selectedDay: Binding<Date?>,
        scope: Binding<CalendarView.Scope>,
        changeMonth: @escaping (Int) -> Void,
        showDay: @escaping (Date) -> Void
    ) {
        self.month = month
        _selectedDay = selectedDay
        _scope = scope
        self.changeMonth = changeMonth
        self.showDay = showDay
        // The month plus a week either side, for the padding days in the grid.
        let interval = FeedCalendar.monthInterval(containing: month)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
        let end = calendar.date(byAdding: .day, value: 7, to: interval.end) ?? interval.end
        _sessions = Query(FeedingSession.completedFeeds(from: start, to: end))
        _pumpSessions = Query(FeedingSession.completedPumps(from: start, to: end))
    }

    var body: some View {
        let entries = sessions.compactMap(\.feedEntry)
        let pumps = pumpSessions.compactMap(\.pumpEntry)
        let now = Date.now
        let grid = FeedCalendar.month(month, entries: entries, pumps: pumps, now: now)
        let unit = bottleModel?.unit ?? .milliliters
        let pumpUnit = pumpModel?.unit ?? unit
        let isCurrentMonth = month == FeedCalendar.startOfMonth(now)

        ScrollView {
            VStack(alignment: .leading, spacing: NBSpacing.l) {
                HStack {
                    Spacer()
                    ScopePicker(scope: $scope)
                }
                Card(padding: NBSpacing.m) {
                    VStack(spacing: NBSpacing.m) {
                        monthHeader(isCurrentMonth: isCurrentMonth)
                        MonthGrid(grid: grid, selectedDay: selectedDay) { cell in
                            select(cell)
                        }
                        .opacity(grid.isEmpty ? 0.6 : 1)
                        .gesture(swipe(isCurrentMonth: isCurrentMonth))
                        CalendarLegend()
                    }
                }

                if let selectedDay {
                    let summary = FeedCalendar.daySummary(selectedDay, entries: entries)
                    DaySummaryCard(
                        day: selectedDay,
                        entries: summary.entries,
                        totals: summary.totals,
                        pumps: FeedCalendar.dayPumps(selectedDay, pumps: pumps),
                        unit: unit,
                        pumpUnit: pumpUnit
                    )
                } else if grid.isEmpty {
                    Text("No feeds this month")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, NBSpacing.l)
                } else {
                    PeriodSummary(title: "This month", totals: grid.totals, pumps: grid.pumps, unit: unit, pumpUnit: pumpUnit)
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
                if cell.hadPump { dot(NBColor.pump) }
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
        if let pumping = PumpCountText.spoken(cell.pumpCount) { parts.append(pumping) }
        return parts.joined(separator: ", ")
    }
}

/// The selected day: totals, the L/R split, its feeds, its pumping, and a link to the full day.
private struct DaySummaryCard: View {
    let day: Date
    let entries: [FeedEntry]
    let totals: FeedTotals
    let pumps: [PumpEntry]
    let unit: VolumeUnit
    let pumpUnit: VolumeUnit

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
                    if !pumps.isEmpty {
                        pumping
                        openDay
                    }
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
                    if !pumps.isEmpty {
                        Divider()
                        pumping
                    }
                    openDay
                }
            }
        }
    }

    /// The day's pumping total, then up to three sessions. Not counted in the feed totals.
    @ViewBuilder
    private var pumping: some View {
        PumpTotalLine(summary: PumpSummary(entries: pumps), unit: pumpUnit)
        ForEach(pumps.prefix(3)) { pump in
            PumpRow(entry: pump)
        }
        if pumps.count > 3 {
            Text("and \(pumps.count - 3) more")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var openDay: some View {
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

/// "Pumping · 2 sessions · 240 mL", in rose.
private struct PumpTotalLine: View {
    let summary: PumpSummary
    let unit: VolumeUnit

    var body: some View {
        HStack {
            Label("Pumping", systemImage: PumpText.symbolName)
                .foregroundStyle(NBColor.pump)
            Spacer()
            Text(summary.count == 1 ? String(localized: "1 session") : String(localized: "\(summary.count) sessions"))
                .foregroundStyle(.secondary)
            Text(FeedText.volume(ml: summary.totalML, unit: unit))
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityElement(children: .combine)
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

/// Shown when no day is selected: the week's or month's totals.
private struct PeriodSummary: View {
    let title: LocalizedStringKey
    let totals: FeedTotals
    let pumps: PumpSummary
    let unit: VolumeUnit
    let pumpUnit: VolumeUnit

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                Text(title)
                    .font(.title3.weight(.semibold))
                DayTotalsRow(totals: totals, unit: unit)
                if !pumps.isEmpty {
                    PumpTotalLine(summary: pumps, unit: pumpUnit)
                }
                Text("Tap a day to see its feeds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("With feeds") {
    @Previewable @State var day: Date? = Calendar.current.startOfDay(for: .now)
    let container = try! PersistenceController.makeContainer(.inMemory)
    HistoryPreviewData.insert(into: container.mainContext)
    return NavigationStack { CalendarView(selectedDay: $day).navigationDestination(for: DayRoute.self) { DayFeedsView(day: $0.day) } }
        .modelContainer(container)
        .environment(BottleLogUIModel.preview())
        .environment(PumpLogUIModel.preview())
}

#Preview("Empty") {
    NavigationStack { CalendarView(selectedDay: .constant(.now)) }
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
}
