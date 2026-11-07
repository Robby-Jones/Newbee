import NewbeeKit
import NewbeeShared
import SwiftUI

/// Home. For now this carries only the feeding entry point (Start L / Start R, or the running
/// session); the full dashboard (docs/UX_SPEC.md §3.2) arrives in Phase 5b.
struct DashboardView: View {
    @Environment(FeedingSessionUIModel.self) private var sessionModel: FeedingSessionUIModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NBSpacing.l) {
                if let sessionModel {
                    BreastfeedingQuickStart(model: sessionModel)
                    BottleQuickLogCard()
                } else {
                    ContentUnavailableView(
                        "No feeds yet",
                        systemImage: "house",
                        description: Text("The feeding timer and today's summary arrive in Phase 5.")
                    )
                }
            }
            .padding(NBSpacing.l)
        }
        .background(NBColor.canvas)
        .navigationTitle("Home")
    }
}

/// Start buttons with the suggested side emphasised, or a live card while a feed is running.
struct BreastfeedingQuickStart: View {
    let model: FeedingSessionUIModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let display = model.display(at: context.date)
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                switch display.phase {
                case .notStarted:
                    Text("Breastfeed")
                        .font(.title3.weight(.semibold))
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: NBSpacing.m))
                        : AnyLayout(HStackLayout(spacing: NBSpacing.m))
                    layout {
                        ForEach(Side.allCases, id: \.self) { side in
                            SideButton(side: side, mode: display.mode(for: side), elapsed: nil) {
                                model.startFromHome(side: side)
                            }
                        }
                    }
                case .active, .paused:
                    activeCard(display)
                }
            }
        }
    }

    private func activeCard(_ display: BreastfeedingTimerDisplay) -> some View {
        Button {
            model.openTimer()
        } label: {
            Card {
                HStack(spacing: NBSpacing.m) {
                    if let side = display.activeSide {
                        SideBadge(side: side)
                    } else {
                        Image(systemName: "pause.circle.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: NBSpacing.xs) {
                        Text(display.isPaused ? "Feed paused" : "Feeding now")
                            .font(.headline)
                        Text("L \(DurationText.clock(display.left)) · R \(DurationText.clock(display.right))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TimerText(display.total, size: 28, relativeTo: .title2)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(Color.primary)
        .accessibilityHint("Opens the feeding timer")
    }
}

#Preview("Idle") {
    NavigationStack { DashboardView() }
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
}

#Preview("Feeding") {
    NavigationStack { DashboardView() }
        .environment(FeedingSessionUIModel(controller: PreviewSessionController.activeFixture()))
}
