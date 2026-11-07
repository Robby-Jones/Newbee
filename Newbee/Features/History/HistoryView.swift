import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Every finished feed, breast and bottle, grouped by day (docs/UX_SPEC.md §3.6).
///
/// Tap or swipe right to edit, swipe left to delete (with confirmation and undo), filter by kind,
/// jump to a date, and add a feed that wasn't timed.
struct HistoryView: View {
    @Environment(FeedingSessionUIModel.self) private var model: FeedingSessionUIModel?
    @Query(FeedingSession.completedFeeds()) private var sessions: [FeedingSession]

    @State private var filter: FeedFilter = .all
    @State private var editing: EditTarget?
    @State private var pendingDelete: FeedEntry?
    @State private var jumpDate: Date = .now
    @State private var showingJump = false
    @State private var scrollTarget: UUID?

    private var days: [TimelineDay] {
        FeedTimeline.days(from: sessions.compactMap(\.feedEntry), filter: filter)
    }

    var body: some View {
        let days = days
        ScrollViewReader { proxy in
            List {
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
            .safeAreaInset(edge: .top, spacing: 0) { filterBar }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
        }
        .background(NBColor.canvas)
        .navigationTitle("History")
        .toolbar { toolbar(days: days) }
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
        .sheet(isPresented: $showingJump) {
            jumpSheet(days: days)
        }
        .confirmationDialog(
            "Delete this feed?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete feed", role: .destructive) { model?.deleteFeed(entry) }
        } message: { _ in
            Text("You can undo for a few seconds afterwards.")
        }
    }

    // MARK: - Rows

    private func rowView(_ row: TimelineRow) -> some View {
        let entry = row.entry
        let canEdit = model != nil && entry.kind == .breast
        return Button {
            edit(entry)
        } label: {
            FeedRow(row: row)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model != nil {
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
        // Bottle feeds open the Log Bottle sheet once bottle editing lands.
        guard entry.kind == .breast, let session = sessions.first(where: { $0.id == entry.id }) else { return }
        editing = .breast(session.sessionSnapshot)
    }

    // MARK: - Chrome

    private var filterBar: some View {
        Picker("Show", selection: $filter) {
            Text("All").tag(FeedFilter.all)
            Text("Breast").tag(FeedFilter.breast)
            Text("Bottle").tag(FeedFilter.bottle)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, NBSpacing.l)
        .padding(.vertical, NBSpacing.s)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private func toolbar(days: [TimelineDay]) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                jumpDate = days.first?.day ?? .now
                showingJump = true
            } label: {
                Label("Jump to date", systemImage: "calendar")
            }
            .disabled(days.isEmpty)
        }
        if model != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Breastfeed", systemImage: "heart") { editing = .newBreast }
                } label: {
                    Label("Add feed", systemImage: "plus")
                }
            }
        }
    }

    private func jumpSheet(days: [TimelineDay]) -> some View {
        NavigationStack {
            DatePicker("Date", selection: $jumpDate, in: (days.last?.day ?? .now)...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Jump to date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingJump = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            showingJump = false
                            // The newest day on or before the chosen date (days are newest first).
                            let chosen = Calendar.current.startOfDay(for: jumpDate)
                            let day = days.first(where: { $0.day <= chosen }) ?? days.last
                            scrollTarget = day?.rows.first?.id
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
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
                description: Text("Choose All to see every feed.")
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
