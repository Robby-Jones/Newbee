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
                SessionSummaryView(session: summary) { note in
                    model.saveNote(note, sessionID: summary.id)
                    model.closeTimer()
                }
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

/// The timer, laid out like a nursing timer (docs/UX_SPEC.md §3.3): the total on top, two big
/// round side buttons with each side's time inside, then Pause, End feed and Add note.
///
/// Dragging down anywhere above Pause minimizes the screen: the content follows the finger and
/// either minimizes on release or springs back. A grabber at the top shows the gesture is there
/// and is also a tappable Minimize button (VoiceOver, Switch Control, and when the screen scrolls).
///
/// In dark mode the app's dark tokens give it a dim, low-glare night look for 3 a.m. feeds.
private struct TimerContent: View {
    let model: FeedingSessionUIModel
    let display: BreastfeedingTimerDisplay

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingStart = false
    @State private var startDraft = Date.now
    @State private var editingNote = false
    @State private var noteDraft = ""
    /// How far the screen has been dragged down toward minimizing.
    @State private var dragOffset: CGFloat = 0
    /// True while a minimize drag is moving, so a drag that starts and ends on a side button
    /// doesn't also count as a tap on it.
    @State private var isDragging = false
    /// The drag-to-minimize gesture is off while the content is taller than the screen (large
    /// accessibility text sizes), so it never fights scrolling; the grabber still works then.
    @State private var contentScrolls = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: NBSpacing.xl) {
                    VStack(spacing: NBSpacing.xl) {
                        grabber
                        if display.phase != .notStarted {
                            topBar
                        }
                        Spacer(minLength: 0)
                        header
                        Spacer(minLength: 0)
                        sideButtons
                        if display.phase != .notStarted {
                            SegmentBar(left: display.left, right: display.right)
                                .frame(maxWidth: 240)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(minimizeDrag, including: contentScrolls ? .subviews : .all)
                    if display.phase != .notStarted {
                        controls
                    }
                }
                .padding(.horizontal, NBSpacing.l)
                .padding(.bottom, NBSpacing.l)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            // When everything fits there is nothing to scroll, so the scroll view stays out of
            // the way of the minimize drag.
            .scrollDisabled(!contentScrolls)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height > geometry.containerSize.height + 1
            } action: { _, scrolls in
                contentScrolls = scrolls
            }
        }
        .offset(y: dragOffset)
        .opacity(1 - min(dragOffset / 600, 0.3))
        .animation(reduceMotion ? nil : .nbState, value: display.phase)
        .sheet(isPresented: $editingStart) { editStartSheet }
        .sheet(isPresented: $editingNote) { noteSheet }
    }

    // MARK: Minimize

    /// Distance, or predicted fling distance, past which releasing a drag minimizes.
    private static let minimizeThreshold: CGFloat = 120

    private var minimizeDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                // Only a mostly-downward drag counts; sideways or upward drags are left alone.
                let dy = value.translation.height
                guard isDragging || (dy > 0 && dy > abs(value.translation.width)) else { return }
                isDragging = true
                dragOffset = max(0, dy)
            }
            .onEnded { value in
                guard isDragging else { return }
                let shouldMinimize = value.translation.height > Self.minimizeThreshold
                    || value.predictedEndTranslation.height > Self.minimizeThreshold * 2.5
                if shouldMinimize {
                    model.closeTimer()
                } else {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { dragOffset = 0 }
                }
                // Cleared after this touch has been handled, so a button released at the end
                // of the drag still sees it and ignores the touch.
                Task { @MainActor in isDragging = false }
            }
    }

    /// The handle at the top: shows the screen can be pulled down, and taps to minimize.
    private var grabber: some View {
        Button {
            model.closeTimer()
        } label: {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Minimize")
        .accessibilityHint(display.phase == .notStarted ? "Back to Home" : "The feed keeps running")
        .padding(.top, -NBSpacing.s)
        .padding(.bottom, -NBSpacing.xl)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Edit start") {
                startDraft = display.startedAt ?? .now
                editingStart = true
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: NBLayout.minHitTarget)
            .accessibilityHint("Change when this feed started")
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
            }
            .saturation(display.isPaused ? 0.3 : 1)
            .opacity(display.isPaused ? 0.75 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timerHeader")
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
                    guard !isDragging else { return }
                    model.tapSide(side)
                }
            }
        }
    }

    // MARK: Pause / End

    private var controls: some View {
        VStack(spacing: NBSpacing.m) {
            Button {
                model.togglePause()
            } label: {
                Label(display.isPaused ? "Resume" : "Pause", systemImage: display.isPaused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(display.isPaused ? NBColor.accent : Color.secondary.opacity(0.18))
            .foregroundStyle(display.isPaused ? Color.white : Color.primary)

            Button {
                model.endSession()
            } label: {
                Label("End feed", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(NBColor.destructive.opacity(0.16))
            .foregroundStyle(NBColor.destructive)
            .accessibilityHint("Saves the feed. You can undo for a few seconds.")

            Button {
                noteDraft = model.activeSession?.notes ?? ""
                editingNote = true
            } label: {
                Label(hasNote ? "Edit note" : "Add note", systemImage: "note.text")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: NBLayout.minHitTarget)
            }
            .tint(NBColor.accent)
        }
        .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
    }

    private var hasNote: Bool {
        !(model.activeSession?.notes.isEmpty ?? true)
    }

    // MARK: Sheets

    private var editStartSheet: some View {
        NavigationStack {
            DatePicker(
                "Started",
                selection: $startDraft,
                in: ...(model.latestStart(at: .now) ?? .now),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .navigationTitle("Feed started at")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingStart = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.editStart(to: startDraft)
                        editingStart = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var noteSheet: some View {
        NavigationStack {
            ScrollView {
                NotesEditor(text: $noteDraft, minLines: 6, fieldIdentifier: "timer.note")
                    .padding(NBSpacing.l)
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingNote = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let id = model.activeSession?.id {
                            model.saveNote(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines), sessionID: id)
                        }
                        editingNote = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
