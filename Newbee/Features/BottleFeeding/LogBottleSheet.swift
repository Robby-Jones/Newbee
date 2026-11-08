import NewbeeKit
import NewbeeShared
import SwiftUI

/// Log Bottle sheet (docs/UX_SPEC.md §3.4). Two-tap path: open → preset → Save.
/// The same sheet edits an existing entry when the draft carries an ID.
struct LogBottleSheet: View {
    let model: BottleLogUIModel

    @State private var draft: BottleDraft
    @State private var amountText: String
    @State private var hasDuration: Bool
    @State private var durationMinutes: Int
    @State private var confirmingDelete = false
    @FocusState private var amountFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: BottleLogUIModel, draft: BottleDraft) {
        self.model = model
        _draft = State(initialValue: draft)
        _amountText = State(initialValue: draft.amount.value > 0 ? draft.amount.formattedValue : "")
        _hasDuration = State(initialValue: draft.durationSeconds != nil)
        _durationMinutes = State(initialValue: max(1, Int(((draft.durationSeconds ?? 600) / 60).rounded())))
    }

    /// The draft as it would be saved, including the duration controls.
    private var finalDraft: BottleDraft {
        var result = draft
        result.durationSeconds = hasDuration ? TimeInterval(durationMinutes * 60) : nil
        return result
    }

    private var problems: [BottleValidationError] {
        model.problems(with: finalDraft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NBSpacing.l) {
                    contentsPicker
                    amountCard
                    timeCard
                    notesCard
                    if let problem = problems.first, draft.amount.value > 0 || !amountText.isEmpty {
                        Label(problem.message, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(NBColor.destructive)
                            .accessibilityIdentifier("bottle.validation")
                    }
                    if draft.isEditing {
                        Button("Delete bottle feed", role: .destructive) {
                            confirmingDelete = true
                        }
                        .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                    }
                }
                .padding(NBSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NBColor.canvas)
            .navigationTitle(draft.isEditing ? "Edit bottle" : "Log bottle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) { saveButton }
            .confirmationDialog("Delete this bottle feed?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = draft.id { model.delete(id: id) }
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .onChange(of: amountText) { _, text in
            draft.amount = BottleAmount.parse(text, unit: draft.amount.unit) ?? BottleAmount(0, draft.amount.unit)
        }
    }

    // MARK: - Sections

    private var contentsPicker: some View {
        Picker("Contents", selection: $draft.contents) {
            ForEach(BottleContents.allCases, id: \.self) { contents in
                Text(contents.title).tag(contents)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("bottle.contents")
    }

    private var amountCard: some View {
        Card {
            VStack(spacing: NBSpacing.m) {
                HStack(spacing: NBSpacing.m) {
                    stepButton(-1, systemImage: "minus", label: "Less")
                    HStack(alignment: .firstTextBaseline, spacing: NBSpacing.xs) {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(NBFont.timer(size: 44))
                            .focused($amountFocused)
                            .fixedSize()
                            .accessibilityLabel("Amount")
                            .accessibilityValue(draft.amount.formatted)
                            .accessibilityIdentifier("bottle.amount")
                        Text(draft.amount.unit.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    stepButton(1, systemImage: "plus", label: "More")
                }

                HStack(spacing: NBSpacing.s) {
                    ForEach(model.presets, id: \.self) { preset in
                        PresetChip(title: preset.formatted, isSelected: approximatelyEqual(preset, draft.amount)) {
                            setAmount(preset)
                        }
                        .accessibilityIdentifier("bottle.preset.\(preset.formattedValue)")
                    }
                }

                Picker("Unit", selection: unitBinding) {
                    ForEach(VolumeUnit.allCases, id: \.self) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("bottle.unit")
            }
        }
    }

    private var timeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                HStack {
                    DatePicker("Start time", selection: $draft.startedAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("bottle.time")
                }
                if abs(draft.startedAt.timeIntervalSinceNow) > 60 {
                    Button("Set to now") { draft.startedAt = .now }
                        .font(.subheadline.weight(.semibold))
                }
                Divider()
                Toggle("Duration", isOn: $hasDuration.animation())
                    .accessibilityIdentifier("bottle.hasDuration")
                if hasDuration {
                    Stepper(value: $durationMinutes, in: 1...Int(model.log.rules.maximumDuration / 60)) {
                        Text(DurationText.short(TimeInterval(durationMinutes * 60)))
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("bottle.duration")
                }
            }
        }
    }

    /// Always visible and roomy, with one-tap tags (docs/UX_SPEC.md §3.4).
    private var notesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.s) {
                Text("Notes")
                    .font(.headline)
                NotesEditor(
                    text: $draft.notes,
                    placeholder: "Anything to remember? How much was left, spit-up…",
                    tags: NotesEditor.bottleTags,
                    minLines: 3,
                    fieldIdentifier: "bottle.notes"
                )
            }
        }
    }

    private var saveButton: some View {
        Button {
            if model.save(finalDraft) { dismiss() }
        } label: {
            Text(draft.isEditing ? "Save changes" : "Save")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
        .tint(NBColor.accent)
        .disabled(!problems.isEmpty)
        .padding(.horizontal, NBSpacing.l)
        .padding(.vertical, NBSpacing.s)
        .background(.bar)
        .accessibilityIdentifier("bottle.save")
    }

    // MARK: - Helpers

    private func stepButton(_ steps: Int, systemImage: String, label: LocalizedStringKey) -> some View {
        Button {
            setAmount(draft.amount.stepped(by: steps, maximumML: model.log.rules.maximumML))
        } label: {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: NBLayout.minHitTarget + 8, height: NBLayout.minHitTarget + 8)
                .background(NBColor.accent.opacity(0.12), in: .circle)
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(NBColor.accent)
        .accessibilityLabel(label)
    }

    private var unitBinding: Binding<VolumeUnit> {
        Binding(
            get: { draft.amount.unit },
            set: { unit in
                guard unit != draft.amount.unit else { return }
                setAmount(draft.amount.value > 0 ? draft.amount.converted(to: unit) : BottleAmount(0, unit))
                model.preferences.volumeUnit = unit
            }
        )
    }

    private func setAmount(_ amount: BottleAmount) {
        draft.amount = amount
        amountText = amount.value > 0 ? amount.formattedValue : ""
    }

    private func approximatelyEqual(_ a: BottleAmount, _ b: BottleAmount) -> Bool {
        a.unit == b.unit && abs(a.value - b.value) < 0.01
    }
}

/// A quick-pick amount ("90 mL"). At least 44 pt tall.
struct PresetChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                .background(
                    NBColor.accent.opacity(isSelected ? 0.28 : 0.12),
                    in: .rect(cornerRadius: NBRadius.control, style: .continuous)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: NBRadius.control, style: .continuous)
                            .strokeBorder(NBColor.accent, lineWidth: 2)
                    }
                }
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("New") {
    let model = BottleLogUIModel.preview()
    return Color.clear.sheet(isPresented: .constant(true)) {
        LogBottleSheet(model: model, draft: model.log.newDraft(unit: .milliliters))
    }
}
