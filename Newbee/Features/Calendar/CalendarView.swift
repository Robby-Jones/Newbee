import SwiftUI

/// Phase 4 shell. Replaced by the real screen in Phase 5 (docs/UX_SPEC.md).
struct CalendarView: View {
    var body: some View {
        ContentUnavailableView(
            "No feeds yet",
            systemImage: "calendar",
            description: Text("The monthly feeding calendar arrives in Phase 5.")
        )
        .navigationTitle("Calendar")
    }
}

#Preview {
    NavigationStack { CalendarView() }
}
