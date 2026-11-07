import NewbeeKit
import NewbeeShared
import SwiftUI

/// Full-screen breastfeeding timer (docs/UX_SPEC.md §3.3).
///
/// Every number on screen is re-derived from the session snapshot once a second by
/// `TimelineView`. The view holds no timer, so leaving the screen changes nothing.
struct BreastfeedingTimerView: View {
    let model: FeedingSessionUIModel

    var body: some View {
        Group {
            if let summary = model.completedSummary, model.activeSession == nil {
                SessionSummaryView(session: summary) { model.closeTimer() }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    TimerContent(model: model, display: model.display(at: context.date))
                }
            }
        }
        .background(NBColor.canvas.ignoresSafeArea())
        .undoToastHost(model)
        .sensoryFeedback(trigger: model.feedback) { _, event in event?.sensoryFeedback }
        .sheet(item: recoveryBinding) { prompt in
            RecoverySheet(prompt: prompt, model: model)
        }
        .feedingErrorAlert(model)
    }

    /// The recovery sheet is presented from here while the timer is up, and from the root otherwise.
    private var recoveryBinding: Binding<RecoveryPrompt?> {
        Binding(get: { model.recoveryPrompt }, set: { _ in })
    }
}

private struct TimerContent: View {
    let model: FeedingSessionUIModel
    let display: BreastfeedingTimerDisplay

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: NBSpacing.xl) {
                    topBar
                    Spacer(minLength: 0)
                    header
                    Spacer(minLength: 0)
                    sideButtons
                    if display.phase != .notStarted {
                        controls
                    }
                }
                .padding(.horizontal, NBSpacing.l)
                .padding(.bottom, NBSpacing.l)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(reduceMotion ? nil : .nbState, value: display.phase)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                model.closeTimer()
            } label: {
                Label("Minimise", systemImage: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: NBLayout.minHitTarget)
            }
            .accessibilityHint("The feed keeps running")
            Spacer()
            if display.phase != .notStarted {
                Menu {
                    Button("Discard feed", systemImage: "trash", role: .destructive) {
                        model.discardSession()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(minWidth: NBLayout.minHitTarget, minHeight: NBLayout.minHitTarget)
                }
                .accessibilityLabel("More")
            }
        }
        .tint(NBColor.accent)
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        switch display.phase {
        case .notStarted:
            notStartedHeader
        case .active, .paused:
            VStack(spacing: NBSpacing.s) {
                HStack(spacing: NBSpacing.xs) {
                    if display.isPaused {
                        Image(systemName: "pause.fill")
                    }
                    Text(display.isPaused ? "Paused" : "Total")
                }
                .font(.headline)
                .foregroundStyle(.secondary)

                TimerText(display.total)
                    .accessibilityLabel(Text("Total feeding time"))
                    .accessibilityValue(Text(DurationText.spoken(display.total)))

                if let startedAt = display.startedAt {
                    Text("Started \(startedAt, format: .dateTime.hour().minute())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                SegmentBar(left: display.left, right: display.right)
                    .frame(maxWidth: 240)
                    .padding(.top, NBSpacing.xs)
            }
            .saturation(display.isPaused ? 0.3 : 1)
            .opacity(display.isPaused ? 0.75 : 1)
            .accessibilityElement(children: .combine)
        }
    }

    private var notStartedHeader: some View {
        VStack(spacing: NBSpacing.s) {
            Image(systemName: "drop.fill")
                .font(.largeTitle)
                .foregroundStyle(NBColor.accent)
                .accessibilityHidden(true)
            Text("Ready when you are")
                .font(.title2.weight(.semibold))
            if let ended = display.lastFeedEnded, let side = display.lastFeedSide {
                Text("Last feed ended \(ended, format: .relative(presentation: .named)) on the \(side.title.lowercased())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let suggested = display.suggestedSide {
                Label {
                    Text("Start on the \(suggested.title.lowercased()) next")
                } icon: {
                    SideBadge(side: suggested)
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Side buttons

    private var sideButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: NBSpacing.m))
            : AnyLayout(HStackLayout(spacing: NBSpacing.m))
        return layout {
            ForEach(Side.allCases, id: \.self) { side in
                SideButton(
                    side: side,
                    mode: display.mode(for: side),
                    elapsed: display.phase == .notStarted ? nil : display.elapsed(on: side)
                ) {
                    model.tapSide(side)
                }
            }
        }
    }

    // MARK: Pause / End

    private var controls: some View {
        HStack(spacing: NBSpacing.m) {
            Button {
                model.togglePause()
            } label: {
                Label(display.isPaused ? "Resume" : "Pause", systemImage: display.isPaused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(display.isPaused ? NBColor.accent : Color.secondary.opacity(0.25))
            .foregroundStyle(display.isPaused ? Color.white : Color.primary)

            Button {
                model.endSession()
            } label: {
                Label("End feed", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
            }
            .buttonStyle(.bordered)
            .tint(NBColor.destructive)
            .accessibilityHint("Saves the feed. You can undo for a few seconds.")
        }
        .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
    }
}

// MARK: - Error alert

extension View {
    func feedingErrorAlert(_ model: FeedingSessionUIModel) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Previews

#Preview("Not started") {
    BreastfeedingTimerView(model: FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()))
}

#Preview("Active") {
    BreastfeedingTimerView(model: FeedingSessionUIModel(controller: PreviewSessionController.activeFixture()))
}

#Preview("Paused") {
    BreastfeedingTimerView(model: FeedingSessionUIModel(controller: PreviewSessionController.pausedFixture()))
}

#Preview("Active, dark, AX size") {
    BreastfeedingTimerView(model: FeedingSessionUIModel(controller: PreviewSessionController.activeFixture()))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
