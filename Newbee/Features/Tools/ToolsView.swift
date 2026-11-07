import SwiftUI

/// Phase 4 shell. Replaced by the real screen in Phase 5 (docs/UX_SPEC.md).
struct ToolsView: View {
    var body: some View {
        ContentUnavailableView(
            "Tools",
            systemImage: "wrench.and.screwdriver",
            description: Text("Calculators, export and settings arrive in Phase 5.")
        )
        .navigationTitle("Tools")
    }
}

#Preview {
    NavigationStack { ToolsView() }
}
