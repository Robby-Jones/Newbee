import SwiftUI

/// Phase 4 shell. Replaced by the real screen in Phase 5 (docs/UX_SPEC.md).
struct DashboardView: View {
    var body: some View {
        ContentUnavailableView(
            "No feeds yet",
            systemImage: "house",
            description: Text("The feeding timer and today's summary arrive in Phase 5.")
        )
        .navigationTitle("Home")
    }
}

#Preview {
    NavigationStack { DashboardView() }
}
