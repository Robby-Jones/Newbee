import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// Every feed on one day, pushed from the Calendar's "Open day", with that day's pumping
/// sessions underneath. Tap an entry to edit it.
struct DayFeedsView: View {
    let day: Date

    @Environment(FeedingSessionUIModel.self) private var model: FeedingSessionUIModel?
    @Environment(BottleLogUIModel.self) private var bottleModel: BottleLogUIModel?
    @Environment(PumpLogUIModel.self) private var pumpModel: PumpLogUIModel?
    @Query private var sessions: [FeedingSession]
    @Query private var pumpSessions: [FeedingSession]
    @State private var editing: SessionSnapshot?

    init(day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        self.day = start
        _sessions = Query(FeedingSession.completedFeeds(from: start, to: end))
        _pumpSessions = Query(FeedingSession.completedPumps(from: start, to: end))
    }

    var body: some View {
        let entries = sessions.compactMap(\.feedEntry)
        let rows = FeedTimeline.days(from: entries).first?.rows ?? []
        let totals = FeedTotals(entries)
        let pumps = pumpSessions.compactMap(\.pumpEntry)
        List {
            if rows.isEmpty && pumps.isEmpty {
                ContentUnavailableView("No feeds on this day", systemImage: "calendar")
                    .listRowBackground(Color.clear)
            } else if !rows.isEmpty {
                Section {
                    let left = entries.reduce(0) { $0 + $1.duration(on: .left) }
                    let right = entries.reduce(0) { $0 + $1.duration(on: .right) }
                    VStack(alignment: .leading, spacing: NBSpacing.s) {
                        DayTotalsRow(totals: totals, unit: bottleModel?.unit ?? .milliliters)
                        if left + right > 0 {
                            SegmentBar(left: left, right: right)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(rows) { row in
                        Button {
                            edit(row.entry)
                        } label: {
                            FeedRow(row: row)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .accessibilityHint(canEdit(row.entry) ? Text("Opens the feed to edit") : Text(""))
                    }
                }
            }
            if !pumps.isEmpty {
                pumpSection(pumps)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(NBColor.canvas)
        .navigationTitle(FeedText.dayTitle(day))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { snapshot in
            if let model {
                BreastFeedEditSheet(model: model, original: snapshot)
            }
        }
    }

    /// "Pumping · 2 sessions · 240 mL", then each session. Pumped milk isn't counted in the
    /// feed totals above.
    private func pumpSection(_ pumps: [PumpEntry]) -> some View {
        let summary = PumpSummary(entries: pumps)
        let unit = pumpModel?.unit ?? bottleModel?.unit ?? .milliliters
        return Section {
            ForEach(pumps) { pump in
                Button {
                    pumpModel?.presentEdit(sessionID: pump.id)
                } label: {
                    PumpRow(entry: pump)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .accessibilityHint(pumpModel != nil ? Text("Opens the session to edit") : Text(""))
            }
        } header: {
            HStack {
                Label("Pumping", systemImage: PumpText.symbolName)
                    .foregroundStyle(NBColor.pumpInk)
                Spacer()
                Text(FeedText.volume(ml: summary.totalML, unit: unit))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
            .accessibilityElement(children: .combine)
        }
    }

    private func canEdit(_ entry: FeedEntry) -> Bool {
        entry.kind == .bottle ? bottleModel != nil : model != nil
    }

    private func edit(_ entry: FeedEntry) {
        if entry.kind == .bottle {
            bottleModel?.presentEdit(sessionID: entry.id)
        } else if let session = sessions.first(where: { $0.id == entry.id }) {
            editing = session.sessionSnapshot
        }
    }
}

#Preview {
    let container = try! PersistenceController.makeContainer(.inMemory)
    HistoryPreviewData.insert(into: container.mainContext)
    return NavigationStack { DayFeedsView(day: .now) }
        .modelContainer(container)
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
        .environment(BottleLogUIModel.preview())
        .environment(PumpLogUIModel.preview())
}
