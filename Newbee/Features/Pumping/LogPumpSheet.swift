import NewbeeKit
import NewbeeShared
import SwiftUI

/// Log Pumping sheet, modelled on Log Bottle: an amount for each side (either may be 0), the
/// unit, when it started and how long it took, and notes. Opens pre-filled from the last
/// session and ending now, so a routine session is one tap on Save. The same sheet edits an
/// existing session when the draft carries an ID.
struct LogPumpSheet: View {
    let model: PumpLogUIModel

    @State private var draft: PumpDraft
    @State private var leftText: String
    @State private var rightText: String
    @State private var hasDuration: Bool
    @State private var durationMinutes: Int
    @State private var confirmingDelete = false
    @FocusState private var focusedSide: Side?
    @Environment(\.dismiss) private var dismiss

    init(model: PumpLogUIModel, draft: PumpDraft) {
        self.model = model
        _draft = State(initialValue: draft)
        _leftText = State(initialValue: Self.text(for: draft.left))
        _rightText = State(initialValue: Self.text(for: draft.right))
        _hasDuration = State(initialValue: draft.durationSeconds != nil)
        _durationMinutes = State(initialValue: max(1, Int(((draft.durationSeconds ?? PumpLog.defaultDuration) / 60).rounded())))
    }

    /// The draft as it would be saved, including the duration controls.
    private var finalDraft: PumpDraft {
        var result = draft
        result.durationSeconds = hasDuration ? TimeInterval(durationMinutes * 60) : nil
        return result
    }

    private var problems: [PumpValidationError] {
        model.problems(with: finalDraft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NBSpacing.l) {
                    amountCard
                    timeCard
                    notesCard
                    if let problem = problems.first {
                        Label(problem.message, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(NBColor.destructive)
                            .accessibilityIdentifier("pump.validation")
                    }
                    if draft.isEditing {
                        Button("Delete pumping session", role: .destructive) {
                            confirmingDelete = true
                        }
                        .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                    }
                }
                .padding(NBSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NBColor.canvas)
            .navigationTitle(draft.isEditing ? "Edit pumping" : "Log pumping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedSide = nil }
                }
            }
            .safeAreaInset(edge: .bottom) { saveButton }
            .confirmationDialog("Delete this pumping session?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = draft.id { model.delete(id: id) }
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .onChange(of: leftText) { _, text in parse(text, side: .left) }
        .onChange(of: rightText) { _, text in parse(text, side: .right) }
    }

    // MARK: - Sections

    private var amountCard: some View {
        Card {
            VStack(spacing: NBSpacing.m) {
                sideRow(.left)
                Divider()
                sideRow(.right)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text(draft.total.formatted)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("pump.total")
                }
                .accessibilityElement(children: .combine)

                Picker("Unit", selection: unitBinding) {
                    ForEach(VolumeUnit.allCases, id: \.self) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("pump.unit")
            }
        }
    }

    /// "L Left   (−)  60 mL  (+)".
    private func sideRow(_ side: Side) -> some View {
        let amount = draft.amount(on: side)
        return HStack(spacing: NBSpacing.m) {
            HStack(spacing: NBSpacing.s) {
                SideBadge(side: side)
                Text(side.title)
                    .font(.headline)
            }
            .frame(minWidth: 72, alignment: .leading)
            Spacer(minLength: 0)
            stepButton(-1, side: side, systemImage: "minus", label: "Less on the \(side.title.lowercased())")
            HStack(alignment: .firstTextBaseline, spacing: NBSpacing.xs) {
                TextField("0", text: side == .left ? $leftText : $rightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(NBFont.timer(size: 32))
                    .focused($focusedSide, equals: side)
                    .fixedSize()
                    .accessibilityLabel("\(side.title) amount")
                    .accessibilityValue(amount.formatted)
                    .accessibilityIdentifier("pump.amount.\(side.rawValue)")
                Text(amount.unit.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NBColor.secondaryText)
            }
            .frame(minWidth: 84)
            stepButton(1, side: side, systemImage: "plus", label: "More on the \(side.title.lowercased())")
        }
    }

    private var timeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                DatePicker("Time", selection: finishedAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("pump.time")
                if abs(finishedAt.wrappedValue.timeIntervalSinceNow) > 60 {
                    Button("Set to now") { finishedAt.wrappedValue = .now }
                        .font(.subheadline.weight(.semibold))
                }
                Divider()
                Toggle("Duration", isOn: durationToggle.animation())
                    .accessibilityIdentifier("pump.hasDuration")
                if hasDuration {
                    Stepper(value: durationStepper, in: 1...Int(model.log.rules.maximumDuration / 60)) {
                        Text(DurationText.short(TimeInterval(durationMinutes * 60)))
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("pump.duration")
                }
            }
        }
    }

    /// Seconds the duration controls currently add after the start.
    private var currentDuration: TimeInterval {
        hasDuration ? TimeInterval(durationMinutes * 60) : 0
    }

    /// The time shown in the sheet is when the session finished (people log pumping once
    /// they're done), so a new entry reads "now". The start is that minus the duration.
    private var finishedAt: Binding<Date> {
        Binding(
            get: { draft.startedAt.addingTimeInterval(currentDuration) },
            set: { draft.startedAt = $0.addingTimeInterval(-currentDuration) }
        )
    }

    /// Changing the duration keeps the finish time and moves the start.
    private var durationStepper: Binding<Int> {
        Binding(
            get: { durationMinutes },
            set: { minutes in
                let end = finishedAt.wrappedValue
                durationMinutes = minutes
                if hasDuration { draft.startedAt = end.addingTimeInterval(-TimeInterval(minutes * 60)) }
            }
        )
    }

    private var durationToggle: Binding<Bool> {
        Binding(
            get: { hasDuration },
            set: { isOn in
                let end = finishedAt.wrappedValue
                hasDuration = isOn
                draft.startedAt = end.addingTimeInterval(isOn ? -TimeInterval(durationMinutes * 60) : 0)
            }
        )
    }

    private var notesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: NBSpacing.s) {
                Text("Notes")
                    .font(.headline)
                NotesEditor(
                    text: $draft.notes,
                    placeholder: "Anything to remember? Where it's stored, how it went…",
                    tags: NotesEditor.pumpTags,
                    minLines: 3,
                    fieldIdentifier: "pump.notes"
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
        .accessibilityIdentifier("pump.save")
    }

    // MARK: - Helpers

    private func stepButton(_ steps: Int, side: Side, systemImage: String, label: String) -> some View {
        Button {
            let stepped = draft.amount(on: side).stepped(by: steps, maximumML: model.log.rules.maximumPerSideML)
            setAmount(stepped, on: side)
        } label: {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: NBLayout.minHitTarget, height: NBLayout.minHitTarget)
                .background(NBColor.side(side).opacity(0.16), in: .circle)
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(NBColor.accent)
        .accessibilityLabel(label)
        .accessibilityIdentifier("pump.\(steps > 0 ? "more" : "less").\(side.rawValue)")
    }

    private var unitBinding: Binding<VolumeUnit> {
        Binding(
            get: { draft.unit },
            set: { unit in
                guard unit != draft.unit else { return }
                draft.convert(to: unit)
                leftText = Self.text(for: draft.left)
                rightText = Self.text(for: draft.right)
                model.preferences.volumeUnit = unit
            }
        )
    }

    private func setAmount(_ amount: BottleAmount, on side: Side) {
        draft.setAmount(amount, on: side)
        let text = Self.text(for: draft.amount(on: side))
        if side == .left { leftText = text } else { rightText = text }
    }

    /// Empty text means 0 for that side.
    private func parse(_ text: String, side: Side) {
        let amount = BottleAmount.parse(text, unit: draft.unit) ?? BottleAmount(0, draft.unit)
        draft.setAmount(amount, on: side)
    }

    private static func text(for amount: BottleAmount) -> String {
        amount.value > 0 ? amount.formattedValue : ""
    }
}

#Preview("New") {
    let model = PumpLogUIModel.preview()
    return Color.clear.sheet(isPresented: .constant(true)) {
        LogPumpSheet(model: model, draft: model.log.newDraft(unit: .milliliters))
    }
}
