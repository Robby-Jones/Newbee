import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Every finished feed, breast and bottle (docs/UX_SPEC.md §3.6), plus pumping sessions, as a
/// day-grouped list or a
/// month calendar (§3.5). One place for looking back, like the history screens in Huckleberry
/// and Apple Fitness.
///
/// In the list: tap or swipe right to edit, swipe left to delete (with confirmation and undo),
/// and filter by kind. Both modes can add a feed that wasn't timed.
struct HistoryView: View {
    enum Mode: Hashable {
        case list, calendar
    }

    @Environment(FeedingSessionUIModel.self) private var model: FeedingSessionUIModel?
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?
    @Query(FeedingSession.completedFeeds()) private var sessions: [FeedingSession]
    @Query(FeedingSession.completedPumps()) private var pumpSessions: [FeedingSession]

    @State private var mode: Mode = .list
    @State private var filter: FeedFilter = .all
    @State private var editing: EditTarget?
    @State private var pendingDelete: HistoryItem?

    var body: some View {
        Group {
            switch mode {
            case .list: list
            case .calendar: CalendarView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { modePicker }
        .background(NBColor.canvas)
        .navigationTitle("History")
        .toolbar { toolbar }
        .navigationDestination(for: DayRoute.self) { route in
            DayFeedsView(day: route.day)
        }
        .sheet(item: $editing) { target in
            if let model {
                switch target {
                case .breast(let snapshot):
                    BreastFeedEditSheet(model: model, original: snapshot)
                case .newBreast:
                    BreastFeedEditSheet(model: model, original: nil, suggestedSide: model.controller.suggestedNextSide)
                }
            }
        }
        .confirmationDialog(
            pendingDelete.map(deleteTitle) ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) { delete(item) }
        } message: { _ in
            Text("You can undo for a few seconds afterwards.")
        }
    }

    private var list: some View {
        let days = HistoryTimeline.days(
            feeds: sessions.compactMap(\.feedEntry),
            pumps: pumpSessions.compactMap(\.pumpEntry),
            filter: filter
        )
        return List {
            if days.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(days) { day in
                    Section {
                        ForEach(day.items) { item in
                            rowView(item)
                        }
                    } header: {
                        Text(FeedText.dayTitle(day.day))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Rows

    private func rowView(_ item: HistoryItem) -> some View {
        let canEdit = canEdit(item)
        return Button {
            edit(item)
        } label: {
            switch item {
            case .feed(let row): FeedRow(row: row)
            case .pump(let entry): PumpRow(entry: entry)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
            }
        }
        .swipeActions(edge: .leading) {
            if canEdit {
                Button("Edit", systemImage: "pencil") { edit(item) }
                    .tint(NBColor.accent)
            }
        }
        .accessibilityHint(canEdit ? Text("Opens it to edit") : Text(""))
    }

    private func canEdit(_ item: HistoryItem) -> Bool {
        switch item {
        case .pump: pumpModel != nil
        case .feed(let row): row.entry.kind == .bottle ? bottleModel != nil : model != nil
        }
    }

    private func deleteTitle(_ item: HistoryItem) -> String {
        if case .pump = item { return String(localized: "Delete this pumping session?") }
        return String(localized: "Delete this feed?")
    }

    private func edit(_ item: HistoryItem) {
        let entry: FeedEntry
        switch item {
        case .pump(let pump):
            pumpModel?.presentEdit(sessionID: pump.id)
            return
        case .feed(let row):
            entry = row.entry
        }
        if entry.kind == .bottle {
            bottleModel?.presentEdit(sessionID: entry.id)
            return
        }
        guard let session = sessions.first(where: { $0.id == entry.id }) else { return }
        editing = .breast(session.sessionSnapshot)
    }

    /// Breastfeeds go through the session manager (keeps "last side" right); bottles through
    /// the bottle log; pumping through the pump log. All offer undo.
    private func delete(_ item: HistoryItem) {
        let entry: FeedEntry
        switch item {
        case .pump(let pump):
            pumpModel?.delete(id: pump.id)
            return
        case .feed(let row):
            entry = row.entry
        }
        if entry.kind == .bottle {
            bottleModel?.delete(id: entry.id)
        } else {
            model?.deleteFeed(id: entry.id)
        }
    }

    // MARK: - Chrome

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            Text("List").tag(Mode.list)
            Text("Calendar").tag(Mode.calendar)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("history.mode")
        .padding(.horizontal, NBSpacing.l)
        .padding(.vertical, NBSpacing.s)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if mode == .list {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Show", selection: $filter) {
                        Label("All feeds", systemImage: "list.bullet").tag(FeedFilter.all)
                        Label("Breastfeeds", systemImage: "heart").tag(FeedFilter.breast)
                        Label("Bottles", systemImage: "waterbottle").tag(FeedFilter.bottle)
                        Label("Pumping", systemImage: PumpText.symbolName).tag(FeedFilter.pump)
                    }
                } label: {
                    Label("Filter", systemImage: filter == .all
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityIdentifier("history.filter")
            }
        }
        if model != nil || bottleModel != nil || pumpModel != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if model != nil {
                        Button("Breastfeed", systemImage: "heart") { editing = .newBreast }
                    }
                    if let bottleModel {
                        Button("Bottle", systemImage: "waterbottle") { bottleModel.presentNew() }
                    }
                    if let pumpModel {
                        Button("Pumping", systemImage: PumpText.symbolName) { pumpModel.presentNew() }
                    }
                } label: {
                    Label("Add feed", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if sessions.isEmpty && pumpSessions.isEmpty {
            ContentUnavailableView(
                "Your feeds will appear here",
                systemImage: "list.bullet",
                description: Text("Finished breastfeeds, bottles and pumping sessions show up in this timeline, newest first.")
            )
        } else {
            ContentUnavailableView(
                emptyFilterTitle,
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Choose All feeds in the filter menu to see every feed.")
            )
        }
    }
}

extension HistoryView {
    fileprivate var emptyFilterTitle: LocalizedStringKey {
        switch filter {
        case .bottle: "No bottle feeds yet"
        case .pump: "No pumping sessions yet"
        default: "No breastfeeds yet"
        }
    }
}

/// What the edit sheet is showing.
private enum EditTarget: Identifiable {
    case breast(SessionSnapshot)
    case newBreast

    var id: String {
        switch self {
        case .breast(let snapshot): snapshot.id.uuidString
        case .newBreast: "new-breast"
        }
    }
}

#Preview("With feeds") {
    let container = try! PersistenceController.makeContainer(.inMemory)
    HistoryPreviewData.insert(into: container.mainContext)
    return NavigationStack { HistoryView() }
        .modelContainer(container)
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
        .environment(BottleLogUIModel.preview())
        .environment(PumpLogUIModel.preview())
}

#Preview("Empty") {
    NavigationStack { HistoryView() }
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
}

/// Sample feeds for previews: breastfeeds and bottles over the last two days.
@MainActor
enum HistoryPreviewData {
    static func insert(into context: ModelContext, now: Date = .now) {
        let hour: TimeInterval = 3_600
        for index in 0..<8 {
            let start = now.addingTimeInterval(-Double(index) * 2.75 * hour - hour)
            if index % 3 == 2 {
                let session = FeedingSession(kind: .bottle, status: .completed, startedAt: start, source: .manual)
                session.endedAt = start
                context.insert(session)
                let details = BottleDetails(contents: index % 2 == 0 ? .formula : .breastMilk, amountML: 90, enteredUnit: .milliliters)
                context.insert(details)
                session.bottle = details
            } else {
                let first: Side = index % 2 == 0 ? .left : .right
                let mid = start.addingTimeInterval(12 * 60)
                let end = mid.addingTimeInterval(9 * 60)
                let snapshot = SessionSnapshot(
                    status: .completed,
                    segments: [Segment(side: first, start: start, end: mid), Segment(side: first.opposite, start: mid, end: end)],
                    startedAt: start,
                    endedAt: end,
                    needsReview: index == 4,
                    notes: index == 0 ? "Sleepy, short latch" : ""
                )
                let session = FeedingSession(id: snapshot.id, kind: .breast, status: .completed, startedAt: start)
                context.insert(session)
                session.apply(snapshot, in: context)
            }
        }
        try? context.save()
    }
}
