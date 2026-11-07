import NewbeeShared
import SwiftData
import SwiftUI

/// Five-tab navigation (docs/UX_SPEC.md §1), plus the global feeding UI: the Active Session
/// Pill above the tab bar, the full-screen timer, the recovery sheet and the undo toast.
struct RootView: View {
    enum TabID: Hashable {
        case home, calendar, history, insights, tools
    }

    /// `nil` only when no session manager is available (Release builds before integration).
    let sessionModel: FeedingSessionUIModel?

    @State private var selection: TabID = .home

    init(sessionModel: FeedingSessionUIModel? = nil) {
        self.sessionModel = sessionModel
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: TabID.home) {
                NavigationStack { DashboardView() }
                    .activeSessionPillInset(sessionModel)
            }
            Tab("Calendar", systemImage: "calendar", value: TabID.calendar) {
                NavigationStack { CalendarView() }
                    .activeSessionPillInset(sessionModel)
            }
            Tab("History", systemImage: "list.bullet", value: TabID.history) {
                NavigationStack { HistoryView() }
                    .activeSessionPillInset(sessionModel)
            }
            Tab("Insights", systemImage: "chart.bar", value: TabID.insights) {
                NavigationStack { InsightsView() }
                    .activeSessionPillInset(sessionModel)
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: TabID.tools) {
                NavigationStack { ToolsView() }
                    .activeSessionPillInset(sessionModel)
            }
        }
        .tint(NBColor.accent)
        .environment(sessionModel)
        .modifier(FeedingPresentation(model: sessionModel))
    }
}

/// Presents the timer cover, recovery sheet and undo toast for the whole app.
private struct FeedingPresentation: ViewModifier {
    let model: FeedingSessionUIModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let model {
            content
                .animation(reduceMotion ? nil : .nbState, value: model.activeSession?.id)
                .undoToastHost(model)
                .sensoryFeedback(trigger: model.feedback) { _, event in
                    // While the timer is up it plays its own feedback.
                    model.isTimerPresented ? nil : event?.sensoryFeedback
                }
                .fullScreenCover(isPresented: Binding(get: { model.isTimerPresented }, set: { model.isTimerPresented = $0 })) {
                    BreastfeedingTimerView(model: model)
                }
                .sheet(item: Binding(get: { model.isTimerPresented ? nil : model.recoveryPrompt }, set: { _ in })) { prompt in
                    RecoverySheet(prompt: prompt, model: model)
                }
                .feedingErrorAlert(model)
        } else {
            content
        }
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

#Preview("Idle") {
    RootView(sessionModel: FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
}

#Preview("Feeding in progress") {
    RootView(sessionModel: FeedingSessionUIModel(controller: PreviewSessionController.activeFixture()))
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
}

#Preview("Forgotten timer") {
    RootView(sessionModel: FeedingSessionUIModel(controller: PreviewSessionController.recoveryFixture()))
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
}
