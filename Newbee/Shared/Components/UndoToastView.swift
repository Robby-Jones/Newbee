import NewbeeShared
import SwiftUI
import UIKit

/// "Feed saved · 21 min  [Undo]" capsule. Disappears after `UndoToast.lifetime`.
struct UndoToastView: View {
    let toast: UndoToast
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
        }
        .padding(.leading, NBSpacing.l)
        .padding(.trailing, NBSpacing.s)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, NBSpacing.l)
        .task(id: toast.id) {
            // VoiceOver users get longer, as a toast can be hard to reach in 6 s.
            let lifetime = UIAccessibility.isVoiceOverRunning ? UndoToast.lifetime * 2 : UndoToast.lifetime
            try? await Task.sleep(for: lifetime)
            if !Task.isCancelled { onExpire() }
        }
    }
}

extension View {
    /// Hosts the shared undo toast at the bottom of this view.
    func undoToastHost(_ model: FeedingSessionUIModel) -> some View {
        modifier(UndoToastHost(model: model))
    }
}

private struct UndoToastHost: ViewModifier {
    let model: FeedingSessionUIModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = model.toast {
                UndoToastView(
                    toast: toast,
                    onUndo: { model.undo() },
                    onExpire: { model.dismissToast(id: toast.id) }
                )
                .padding(.bottom, NBSpacing.s)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .nbState, value: model.toast)
    }
}

#Preview {
    let model = FeedingSessionUIModel(controller: PreviewSessionController.idleFixture())
    model.toast = UndoToast(message: "Feed saved · 21 min", snapshot: PreviewSessionController.completedFixture(endingBefore: .now))
    return Color.clear.undoToastHost(model)
}
