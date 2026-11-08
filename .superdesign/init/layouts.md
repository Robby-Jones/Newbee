# Layouts

> Project: Newbee — native iOS 18+ app (SwiftUI, SwiftData, ActivityKit). NOT a web app: no React/Tailwind/CSS. Designs are iPhone screens (390×844 pt) and Live Activity surfaces. UI uses SF Pro / SF Pro Rounded, SF Symbols, system materials.

The app shell is a SwiftUI `TabView` with 4 tabs (Home, History, Insights, Settings), each a `NavigationStack` with a large title. Per-tab bottom chrome: undo toasts float above the Active Session Pill, which floats above the system tab bar. The breastfeeding timer is a full-screen cover; bottle logging and editing are sheets.

### `Newbee/App/RootView.swift`

```swift
import NewbeeShared
import SwiftData
import SwiftUI

/// Four-tab navigation (docs/UX_SPEC.md §1): Home, History (list and calendar), Insights and
/// Settings, plus the global feeding UI: the Active Session Pill above the tab bar, the
/// full-screen timer, the recovery sheet and the undo toast.
struct RootView: View {
    enum TabID: Hashable {
        case home, history, insights, settings
    }

    /// `nil` only when no session manager is available (Release builds before integration).
    let sessionModel: FeedingSessionUIModel?
    /// Log Bottle sheet and its undo toast; `nil` in previews that don't need it.
    let bottleModel: BottleLogUIModel?

    @State private var selection: TabID = .home
    /// Appearance (System / Light / Dark) from Settings.
    @Environment(AppPreferences.self) private var preferences: AppPreferences?

    init(sessionModel: FeedingSessionUIModel? = nil, bottleModel: BottleLogUIModel? = nil) {
        self.sessionModel = sessionModel
        self.bottleModel = bottleModel
    }

    var body: some View {
        // `.tabItem` + `.tag`; the iOS 18 `Tab` API is now available but not adopted yet.
        TabView(selection: $selection) {
            NavigationStack { DashboardView() }
                .tabChrome(sessionModel, bottleModel)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(TabID.home)
            NavigationStack { HistoryView() }
                .tabChrome(sessionModel, bottleModel)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(TabID.history)
            NavigationStack { InsightsView() }
                .tabChrome(sessionModel, bottleModel)
                .tabItem { Label("Insights", systemImage: "chart.bar") }
                .tag(TabID.insights)
            NavigationStack { SettingsView() }
                .tabChrome(sessionModel, bottleModel)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(TabID.settings)
        }
        .tint(NBColor.accent)
        .preferredColorScheme(preferences?.appearance.colorScheme)
        .environment(sessionModel)
        .environment(bottleModel)
        .modifier(FeedingPresentation(model: sessionModel))
        .bottleLogPresentation(bottleModel)
    }
}

private extension View {
    /// Per-tab bottom chrome: the undo toasts float just above the Active Session Pill, which
    /// sits just above the tab bar. Hosting the toasts inside each tab (not over the whole
    /// TabView) keeps them from covering the tab bar for their 6 seconds.
    func tabChrome(_ sessionModel: FeedingSessionUIModel?, _ bottleModel: BottleLogUIModel?) -> some View {
        modifier(FeedingToastHost(model: sessionModel))
            .bottleToastHost(bottleModel)
            .activeSessionPillInset(sessionModel)
    }
}

private struct FeedingToastHost: ViewModifier {
    let model: FeedingSessionUIModel?

    func body(content: Content) -> some View {
        if let model {
            content.undoToastHost(model)
        } else {
            content
        }
    }
}

/// Presents the timer cover, recovery sheet, haptics and errors for the whole app.
private struct FeedingPresentation: ViewModifier {
    let model: FeedingSessionUIModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let model {
            content
                .animation(reduceMotion ? nil : .nbState, value: model.activeSession?.id)
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
    RootView(
        sessionModel: FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()),
        bottleModel: .preview()
    )
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
```
