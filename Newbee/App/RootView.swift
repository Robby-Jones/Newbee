import NewbeeShared
import SwiftData
import SwiftUI

/// Five-tab navigation (docs/UX_SPEC.md §1).
struct RootView: View {
    enum TabID: Hashable {
        case home, calendar, history, insights, tools
    }

    @State private var selection: TabID = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: TabID.home) {
                NavigationStack { DashboardView() }
            }
            Tab("Calendar", systemImage: "calendar", value: TabID.calendar) {
                NavigationStack { CalendarView() }
            }
            Tab("History", systemImage: "list.bullet", value: TabID.history) {
                NavigationStack { HistoryView() }
            }
            Tab("Insights", systemImage: "chart.bar", value: TabID.insights) {
                NavigationStack { InsightsView() }
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: TabID.tools) {
                NavigationStack { ToolsView() }
            }
        }
        .tint(NBColor.accent)
    }
}

/// Shown if the database can't be opened. Never silently resets data.
struct StoreErrorView: View {
    let error: Error?

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't open your feeding data", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error?.localizedDescription ?? "Unknown error.")
            Text("Your data has not been deleted. Try restarting the app.")
        }
    }
}

#Preview {
    RootView()
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
}
