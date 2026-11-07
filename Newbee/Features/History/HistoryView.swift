import SwiftUI

/// Phase 4 shell. Replaced by the real screen in Phase 5 (docs/UX_SPEC.md).
struct HistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "No feeds yet",
            systemImage: "list.bullet",
            description: Text("Your feeding timeline arrives in Phase 5.")
        )
        .navigationTitle("History")
    }
}

#Preview {
    NavigationStack { HistoryView() }
}
