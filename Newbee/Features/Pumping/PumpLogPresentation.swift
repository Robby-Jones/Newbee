import NewbeeKit
import NewbeeShared
import SwiftUI
import UIKit

extension View {
    /// Hosts the Log Pumping sheet, haptics and errors for the whole app.
    func pumpLogPresentation(_ model: PumpLogUIModel?) -> some View {
        modifier(PumpLogPresentation(model: model))
    }

    /// Shows the pumping undo toast at the bottom of this view's safe area, inside each tab so
    /// it sits above the tab bar.
    func pumpToastHost(_ model: PumpLogUIModel?) -> some View {
        modifier(PumpToastHost(model: model))
    }
}

private struct PumpToastHost: ViewModifier {
    let model: PumpLogUIModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let model {
            content
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        PumpToastView(toast: toast, onUndo: { model.undo() }, onExpire: { model.dismissToast(id: toast.id) })
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

private struct PumpLogPresentation: ViewModifier {
    let model: PumpLogUIModel?

    func body(content: Content) -> some View {
        if let model {
            content
                .sheet(item: Binding(get: { model.editor }, set: { model.editor = $0 })) { request in
                    LogPumpSheet(model: model, draft: request.draft)
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

/// "Pumping saved · 120 mL  [Undo]", same look as the other undo toasts.
private struct PumpToastView: View {
    let toast: PumpLogUIModel.Toast
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
                .accessibilityIdentifier("pump.undo")
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

// MARK: - Display

/// Display text for pumping sessions.
enum PumpText {
    /// "Pumping · 120 mL".
    static func title(_ entry: PumpEntry) -> String {
        String(localized: "Pumping · \(entry.totalAmount.formatted)")
    }

    /// "L 70 mL · R 50 mL · 15 min".
    static func detail(_ entry: PumpEntry) -> String {
        var parts = ["L \(entry.amount(on: .left).formatted)", "R \(entry.amount(on: .right).formatted)"]
        if let duration = entry.durationSeconds {
            parts.append(DurationText.short(duration))
        }
        return parts.joined(separator: " · ")
    }
}

/// One pumping session in History and on a day's page: time, rose rail, total, per-side split, note.
struct PumpRow: View {
    let entry: PumpEntry

    var body: some View {
        HStack(alignment: .top, spacing: NBSpacing.m) {
            Text(entry.startedAt, format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)

            Capsule()
                .fill(NBColor.pump)
                .frame(width: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                HStack(spacing: NBSpacing.s) {
                    Image(systemName: PumpText.symbolName)
                        .foregroundStyle(NBColor.pump)
                        .accessibilityHidden(true)
                    Text(PumpText.title(entry))
                        .font(.body.weight(.semibold))
                }
                Text(PumpText.detail(entry))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                if !entry.notes.isEmpty {
                    Label {
                        Text(entry.notes)
                            .lineLimit(6)
                    } icon: {
                        Image(systemName: "note.text")
                            .accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, NBSpacing.s)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NBColor.pump.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NBSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension PumpText {
    /// SF Symbol for pumping.
    static let symbolName = "drop.halffull"
}

// MARK: - Previews

extension PumpLogUIModel {
    /// A model on an in-memory store with a couple of sessions, for previews.
    static func preview() -> PumpLogUIModel {
        let repository = InMemoryPumpRepository(entries: [
            PumpEntry(startedAt: .now.addingTimeInterval(-3 * 3600), leftML: 70, rightML: 50, durationSeconds: 900),
            PumpEntry(startedAt: .now.addingTimeInterval(-7 * 3600), leftML: 60, rightML: 60, durationSeconds: 1200),
        ])
        let defaults = UserDefaults(suiteName: "NewbeePreviews") ?? .standard
        return PumpLogUIModel(
            log: PumpLog(repository: repository, clock: SystemClock()),
            preferences: AppPreferences(defaults: defaults)
        )
    }
}

#Preview {
    let model = PumpLogUIModel.preview()
    return Button("Log pumping") { model.presentNew() }
        .environment(model)
        .pumpLogPresentation(model)
        .pumpToastHost(model)
}
