import NewbeeKit
import NewbeeShared
import SwiftUI

/// Edit or add a finished breastfeed (docs/UX_SPEC.md §3.7).
///
/// Simple mode: start time, first side and time on each side. Segments mode: every side change
/// with its own start and end, for feeds with pauses or several switches. Both produce a
/// `SessionSnapshot` that is checked with the same rules the timer follows before it can be saved.
struct BreastFeedEditSheet: View {
    enum Mode: Hashable {
        case simple, segments
    }

    let model: FeedingSessionUIModel
    /// The stored session, or `nil` when adding a feed by hand.
    let original: SessionSnapshot?

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var simple: SimpleBreastEdit
    @State private var segments: [Segment]
    @State private var notes: String
    @State private var saveError: String?
    @State private var confirmingDelete = false

    init(model: FeedingSessionUIModel, original: SessionSnapshot?, suggestedSide: Side = .left, now: Date = .now) {
        self.model = model
        self.original = original
        let simpleDraft = original.flatMap(SimpleBreastEdit.init)
        let fallback = SimpleBreastEdit.manualEntry(endingAt: now, firstSide: suggestedSide)
        _mode = State(initialValue: original == nil || simpleDraft != nil ? .simple : .segments)
        _simple = State(initialValue: simpleDraft ?? fallback)
        _segments = State(initialValue: original?.segments ?? fallback.newSession().segments)
        _notes = State(initialValue: original?.notes ?? "")
    }

    private var isNew: Bool { original == nil }

    /// Simple mode can't show feeds with pauses or more than one switch.
    private var simpleAvailable: Bool { isNew || original.flatMap(SimpleBreastEdit.init) != nil }

    private var candidate: SessionSnapshot {
        var base = original ?? SessionSnapshot(status: .completed, segments: [], startedAt: simple.start, source: .manual)
        base.notes = notes
        // Saving an edit confirms the times, so any "Review" flag is cleared.
        base.needsReview = false
        switch mode {
        case .simple:
            return simple.apply(to: base)
        case .segments:
            base.segments = segments
            return SessionEditing.normalizedCompleted(base)
        }
    }

    private var problems: [String] {
        let violations = SessionValidator.violations(in: candidate, now: .now)
        var messages: [String] = []
        for violation in violations {
            let message = Self.message(for: violation)
            if !messages.contains(message) { messages.append(message) }
        }
        if mode == .simple, simple.total <= 0 { messages = [String(localized: "Add time on at least one side.")] }
        return messages
    }

    private var hasChanges: Bool {
        guard let original else { return true }
        var unchanged = original
        unchanged.needsReview = false
        return candidate != unchanged || original.needsReview
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                }
                .listRowBackground(Color.clear)

                if simpleAvailable {
                    Section {
                        Picker("Mode", selection: $mode) {
                            Text("Simple").tag(Mode.simple)
                            Text("Side changes").tag(Mode.segments)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { old, new in syncDrafts(from: old, to: new) }
                    }
                }

                switch mode {
                case .simple: simpleSections
                case .segments: segmentSections
                }

                Section("Notes") {
                    NotesEditor(text: $notes)
                        .padding(.vertical, NBSpacing.xs)
                }

                if !problems.isEmpty || saveError != nil {
                    Section {
                        ForEach(problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(NBColor.destructive)
                        }
                        if let saveError {
                            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(NBColor.destructive)
                        }
                    }
                }

                if let original {
                    Section {
                        Button("Delete feed", role: .destructive) { confirmingDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                    .confirmationDialog("Delete this feed?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete feed", role: .destructive) {
                            model.deleteFeed(id: original.id)
                            dismiss()
                        }
                    } message: {
                        Text("You can undo for a few seconds afterwards.")
                    }
                }
            }
            .navigationTitle(isNew ? "Add breastfeed" : "Edit breastfeed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { saveButton }
        }
    }

    /// Feed type and times at the top of the sheet, so it reads like the feed's own page.
    private var header: some View {
        let session = candidate
        let end = session.endedAt ?? session.segments.compactMap(\.end).max() ?? session.startedAt
        return VStack(spacing: NBSpacing.s) {
            Image(systemName: "heart.fill")
                .font(.title)
                .foregroundStyle(NBColor.left)
                .frame(width: 64, height: 64)
                .background(NBColor.left.opacity(0.18), in: .circle)
                .accessibilityHidden(true)
            Text("Breastfeed")
                .font(.title2.weight(.bold))
            Text("\(FeedText.dayTitle(session.startedAt)) · \(session.startedAt, format: .dateTime.hour().minute()) – \(end, format: .dateTime.hour().minute())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Primary action at the bottom, in reach of a thumb (like Log Bottle).
    private var saveButton: some View {
        Button(action: save) {
            Text(isNew ? "Add feed" : "Save")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
        .tint(NBColor.accent)
        .disabled(!problems.isEmpty || !hasChanges)
        .padding(.horizontal, NBSpacing.l)
        .padding(.vertical, NBSpacing.s)
        .background(.bar)
        .accessibilityIdentifier("breastEdit.save")
    }

    // MARK: - Simple mode

    @ViewBuilder
    private var simpleSections: some View {
        Section {
            DatePicker("Start time", selection: $simple.start, in: ...Date.now)
            Picker("First side", selection: $simple.firstSide) {
                ForEach(Side.allCases, id: \.self) { side in
                    Text(side.title).tag(side)
                }
            }
            .pickerStyle(.segmented)
        }
        Section {
            ForEach(Side.allCases, id: \.self) { side in
                let binding = side == .left ? $simple.left : $simple.right
                Stepper(value: binding, in: 0...(3 * 3_600), step: 60) {
                    HStack {
                        SideBadge(side: side, style: binding.wrappedValue > 0 ? .filled : .soft)
                        Text(side.title)
                        Spacer()
                        Text(DurationText.short(binding.wrappedValue))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityValue(DurationText.spoken(binding.wrappedValue))
            }
        } footer: {
            Text("Ends \(simple.end, format: .dateTime.hour().minute()) · total \(DurationText.short(simple.total))")
        }
    }

    // MARK: - Segments mode

    @ViewBuilder
    private var segmentSections: some View {
        Section {
            ForEach($segments) { $segment in
                VStack(alignment: .leading, spacing: NBSpacing.s) {
                    Picker("Side", selection: $segment.side) {
                        ForEach(Side.allCases, id: \.self) { side in
                            Text(side.title).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("From", selection: $segment.start, in: ...Date.now)
                    DatePicker("To", selection: Binding(
                        get: { segment.end ?? segment.start },
                        set: { segment.end = $0 }
                    ), in: ...Date.now)
                    Text(DurationText.short(segment.duration(at: segment.end ?? segment.start)))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, NBSpacing.xs)
            }
            .onDelete { segments.remove(atOffsets: $0) }

            Button {
                segments.append(SessionEditing.nextSegment(after: SessionEditing.normalizedCompleted(candidate)))
            } label: {
                Label("Add side change", systemImage: "plus.circle")
            }
        } header: {
            Text("Side changes")
        } footer: {
            Text("Gaps between side changes count as pauses. Swipe to remove one.")
        }
    }

    // MARK: - Actions

    /// Carries what's been entered across a mode switch.
    private func syncDrafts(from old: Mode, to new: Mode) {
        switch (old, new) {
        case (.simple, .segments):
            segments = simple.apply(to: withSegments([])).segments
        case (.segments, .simple):
            if let draft = SimpleBreastEdit(SessionEditing.normalizedCompleted(withSegments(segments))) {
                simple = draft
            }
        default:
            break
        }
    }

    private func withSegments(_ segments: [Segment]) -> SessionSnapshot {
        var base = original ?? SessionSnapshot(status: .completed, segments: [], startedAt: simple.start, source: .manual)
        base.segments = segments
        return base
    }

    private func save() {
        do {
            if isNew {
                try model.addManualFeed(candidate)
            } else {
                try model.saveEdit(candidate)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private static func message(for violation: SessionInvariantViolation) -> String {
        switch violation {
        case .noSegments: String(localized: "Add time on at least one side.")
        case .segmentEndsBeforeStart: String(localized: "A side ends before it starts.")
        case .segmentsOverlap: String(localized: "Two side changes overlap.")
        case .inFuture: String(localized: "Times can't be in the future.")
        default: String(localized: "Those times don't add up.")
        }
    }
}

#Preview("Edit") {
    BreastFeedEditSheet(
        model: FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()),
        original: PreviewSessionController.completedFixture(endingBefore: .now.addingTimeInterval(-3_600))
    )
}

#Preview("Add") {
    BreastFeedEditSheet(model: FeedingSessionUIModel(controller: PreviewSessionController.idleFixture()), original: nil)
}
