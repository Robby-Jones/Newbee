import SwiftUI

/// Phase 4 shell. Replaced by the real screen in Phase 5 (docs/UX_SPEC.md).
struct InsightsView: View {
    var body: some View {
        ContentUnavailableView(
            "Not enough data",
            systemImage: "chart.bar",
            description: Text("Feeding insights arrive in Phase 5.")
        )
        .navigationTitle("Insights")
    }
}

#Preview {
    NavigationStack { InsightsView() }
}
