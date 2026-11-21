import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI

/// One day pushed from the Calendar's "Open day": its totals, then its feeds and pumping
/// sessions on an hour grid (`DayCalendarPage`). Tap a block to edit it.
struct DayFeedsView: View {
    let day: Date

    init(day: Date) {
        self.day = Calendar.current.startOfDay(for: day)
    }

    var body: some View {
        DayCalendarPage(day: day)
            .navigationTitle(FeedText.dayTitle(day))
            .navigationBarTitleDisplayMode(.inline)
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
