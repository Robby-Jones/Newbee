import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Every finished feed, breast and bottle (docs/UX_SPEC.md §3.6), as a day-grouped list or a
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
    @Query(FeedingSession.completedFeeds()) private var sessions: [FeedingSession]

    @State private var mode: Mode = .list
    @State private var filter: FeedFilter = .all
    @State private var editing: EditTarget?
    @State private var pendingDelete: FeedEntry?

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
            "Delete this feed?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete feed", role: .destructive) { delete(entry) }
        } message: { _ in
            Text("You can undo for a few seconds afterwards.")
        }
    }

    private var list: some View {
        let days = FeedTimeline.days(from: sessions.compactMap(\.feedEntry), filter: filter)
        return List {
            if days.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(days) { day in
                    Section {
                        ForEach(day.rows) { row in
                            rowView(row)
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

    private func rowView(_ row: TimelineRow) -> some View {
        let entry = row.entry
        let canEdit = entry.kind == .bottle ? bottleModel != nil : model != nil
        return Button {
            edit(entry)
        } label: {
            FeedRow(row: row)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
            }
        }
        .swipeActions(edge: .leading) {
            if canEdit {
                Button("Edit", systemImage: "pencil") { edit(entry) }
                    .tint(NBColor.accent)
            }
        }
        .accessibilityHint(canEdit ? Text("Opens the feed to edit") : Text(""))
    }

    private func edit(_ entry: FeedEntry) {
        if entry.kind == .bottle {
            bottleModel?.presentEdit(sessionID: entry.id)
            return
        }
        guard let session = sessions.first(where: { $0.id == entry.id }) else { return }
        editing = .breast(session.sessionSnapshot)
    }

    /// Breastfeeds go through the session manager (keeps "last side" right); bottles through
    /// the bottle log. Both offer undo.
    private func delete(_ entry: FeedEntry) {
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
                    }
                } label: {
                    Label("Filter", systemImage: filter == .all
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityIdentifier("history.filter")
            }
        }
        if model != nil || bottleModel != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if model != nil {
                        Button("Breastfeed", systemImage: "heart") { editing = .newBreast }
                    }
                    if let bottleModel {
                        Button("Bottle", systemImage: "waterbottle") { bottleModel.presentNew() }
                    }
                } label: {
                    Label("Add feed", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "Your feeds will appear here",
                systemImage: "list.bullet",
                description: Text("Finished breastfeeds and bottles show up in this timeline, newest first.")
            )
        } else {
            ContentUnavailableView(
                filter == .bottle ? "No bottle feeds yet" : "No breastfeeds yet",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Choose All feeds in the filter menu to see every feed.")
            )
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
