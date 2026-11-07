import NewbeeKit
import NewbeeShared
import SwiftUI
import UIKit

/// Home card: "Log bottle", today's bottle total and the last few bottles (tap to edit).
struct BottleQuickLogCard: View {
    @Environment(BottleLogUIModel.self) private var model: BottleLogUIModel?

    var body: some View {
        if let model {
            content(model)
                .onAppear { model.refresh() }
        }
    }

    private func content(_ model: BottleLogUIModel) -> some View {
        VStack(alignment: .leading, spacing: NBSpacing.m) {
            Button {
                model.presentNew()
            } label: {
                Card {
                    HStack(spacing: NBSpacing.m) {
                        Image(systemName: "waterbottle.fill")
                            .font(.title2)
                            .foregroundStyle(NBColor.bottleBreastMilk)
                            .frame(width: NBLayout.minHitTarget, height: NBLayout.minHitTarget)
                            .background(NBColor.bottleBreastMilk.opacity(0.18), in: .circle)
                        VStack(alignment: .leading, spacing: NBSpacing.xs) {
                            Text("Log bottle")
                                .font(.headline)
                            Text(todayLine(model))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundStyle(NBColor.accent)
                    }
                }
            }
            .buttonStyle(PressableButtonStyle())
            .foregroundStyle(Color.primary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("logBottleButton")

            if !model.recent.isEmpty {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(model.recent.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().padding(.leading, NBSpacing.l) }
                            BottleRow(entry: entry) { model.presentEdit(sessionID: entry.id) }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { model.presentEdit(sessionID: entry.id) }
                                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete(id: entry.id) }
                                }
                        }
                    }
                }
            }
        }
    }

    private func todayLine(_ model: BottleLogUIModel) -> String {
        let today = model.today
        if today.isEmpty { return String(localized: "None today") }
        let total = model.formatted(ml: today.totalML)
        return today.count == 1
            ? String(localized: "Today: 1 bottle · \(total)")
            : String(localized: "Today: \(today.count) bottles · \(total)")
    }
}

/// One recent bottle: "2:10 PM  90 mL formula  ›".
private struct BottleRow: View {
    let entry: BottleEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NBSpacing.m) {
                Circle()
                    .fill(entry.contents.tint)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BottleLogUIModel.describe(entry))
                        .font(.subheadline.weight(.semibold))
                    Text(entry.startedAt, format: .relative(presentation: .named))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.startedAt, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, NBSpacing.l)
            .frame(minHeight: NBLayout.minHitTarget + 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit this bottle feed")
    }
}

extension BottleContents {
    /// Feed color (docs/UX_SPEC.md §2). Always shown with text, never alone.
    var tint: Color {
        switch self {
        case .breastMilk: NBColor.bottleBreastMilk
        case .formula: NBColor.bottleFormula
        case .other: Color.gray
        }
    }
}

// MARK: - Presentation

extension View {
    /// Hosts the Log Bottle sheet, its undo toast and errors for the whole app.
    func bottleLogPresentation(_ model: BottleLogUIModel?) -> some View {
        modifier(BottleLogPresentation(model: model))
    }
}

private struct BottleLogPresentation: ViewModifier {
    let model: BottleLogUIModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let model {
            content
                .sheet(item: Binding(get: { model.editor }, set: { model.editor = $0 })) { request in
                    LogBottleSheet(model: model, draft: request.draft)
                }
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        BottleToastView(toast: toast, onUndo: { model.undo() }, onExpire: { model.dismissToast(id: toast.id) })
                            .padding(.bottom, NBSpacing.s)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .nbState, value: model.toast)
                .sensoryFeedback(trigger: model.feedback) { _, event in event?.sensoryFeedback }
                .alert(
                    "Something went wrong",
                    isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
        } else {
            content
        }
    }
}

/// "Bottle saved · 90 mL formula  [Undo]", same look as the breastfeeding undo toast.
private struct BottleToastView: View {
    let toast: BottleLogUIModel.Toast
    let onUndo: () -> Void
    let onExpire: () -> Void

    var body: some View {
        HStack(spacing: NBSpacing.m) {
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: NBSpacing.s)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NBColor.accent)
                .frame(minWidth: NBLayout.minHitTarget, minHeight: NBLayout.minHitTarget)
                .accessibilityIdentifier("bottle.undo")
        }
        .padding(.leading, NBSpacing.l)
        .padding(.trailing, NBSpacing.s)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, NBSpacing.l)
        .task(id: toast.id) {
            let lifetime = UIAccessibility.isVoiceOverRunning ? UndoToast.lifetime * 2 : UndoToast.lifetime
            try? await Task.sleep(for: lifetime)
            if !Task.isCancelled { onExpire() }
        }
    }
}

// MARK: - Previews

extension BottleLogUIModel {
    /// A model on an in-memory store with a couple of bottles, for previews.
    static func preview() -> BottleLogUIModel {
        let repository = InMemoryBottleRepository(entries: [
            BottleEntry(startedAt: .now.addingTimeInterval(-2 * 3600), contents: .formula, amountML: 90),
            BottleEntry(startedAt: .now.addingTimeInterval(-5 * 3600), contents: .breastMilk, amountML: 60),
        ])
        let defaults = UserDefaults(suiteName: "NewbeePreviews") ?? .standard
        return BottleLogUIModel(
            log: BottleLog(repository: repository, clock: SystemClock()),
            preferences: AppPreferences(defaults: defaults)
        )
    }
}

#Preview {
    let model = BottleLogUIModel.preview()
    return ScrollView {
        BottleQuickLogCard().padding()
    }
    .background(NBColor.canvas)
    .environment(model)
    .bottleLogPresentation(model)
}
