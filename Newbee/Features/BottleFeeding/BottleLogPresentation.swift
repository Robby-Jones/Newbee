import NewbeeKit
import NewbeeShared
import SwiftUI
import UIKit

// MARK: - Presentation

extension View {
    /// Hosts the Log Bottle sheet, haptics and errors for the whole app.
    func bottleLogPresentation(_ model: BottleLogUIModel?) -> some View {
        modifier(BottleLogPresentation(model: model))
    }

    /// Shows the bottle undo toast at the bottom of this view's safe area. Applied inside each
    /// tab so the toast sits above the tab bar instead of covering it.
    func bottleToastHost(_ model: BottleLogUIModel?) -> some View {
        modifier(BottleToastHost(model: model))
    }
}

private struct BottleToastHost: ViewModifier {
    let model: BottleLogUIModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let model {
            content
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        BottleToastView(toast: toast, onUndo: { model.undo() }, onExpire: { model.dismissToast(id: toast.id) })
                            .padding(.bottom, NBSpacing.s)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .nbState, value: model.toast)
        } else {
            content
        }
    }
}

private struct BottleLogPresentation: ViewModifier {
    let model: BottleLogUIModel?

    func body(content: Content) -> some View {
        if let model {
            content
                .sheet(item: Binding(get: { model.editor }, set: { model.editor = $0 })) { request in
                    LogBottleSheet(model: model, draft: request.draft)
                }
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
    return Button("Log bottle") { model.presentNew() }
        .environment(model)
        .bottleLogPresentation(model)
        .bottleToastHost(model)
}
