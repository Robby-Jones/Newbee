import NewbeeKit
import NewbeeShared
import SwiftUI

/// "Were you still feeding?" (docs/TIMER_ENGINE.md §5). Shown when a session looks wrong, for
/// example a timer left running for hours. It can't be swiped away and never discards on its
/// own: the parent picks what happened.
struct RecoverySheet: View {
    let prompt: RecoveryPrompt
    let model: FeedingSessionUIModel

    @State private var endTime: Date

    init(prompt: RecoveryPrompt, model: FeedingSessionUIModel) {
        self.prompt = prompt
        self.model = model
        let lower = prompt.session.startedAt
        _endTime = State(initialValue: min(max(prompt.suggestedEnd, lower), max(Date(), lower)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NBSpacing.l) {
                header
                if prompt.reason == .clockChanged || prompt.reason == .futureStart, let corrected = prompt.correctedStart {
                    optionButton(
                        String(localized: "Fix start time to \(corrected.formatted(date: .omitted, time: .shortened))"),
                        systemImage: "clock.arrow.circlepath",
                        prominent: true
                    ) { model.recoveryFixStart(to: corrected) }
                }
                optionButton(String(localized: "Keep going"), systemImage: "play.fill", prominent: prompt.correctedStart == nil) {
                    model.recoveryKeepGoing()
                }
                endAtOption
                optionButton(String(localized: "End now"), systemImage: "stop.fill") {
                    model.recoveryEnd(at: nil)
                }
                Button(role: .destructive) {
                    model.recoveryDiscard()
                } label: {
                    Label("Discard this feed", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                }
                .tint(NBColor.destructive)
                .accessibilityHint("You can undo for a few seconds")
            }
            .padding(NBSpacing.xl)
        }
        .background(NBColor.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private var header: some View {
        let side = prompt.session.lastSide ?? .left
        return VStack(alignment: .leading, spacing: NBSpacing.s) {
            Text(title)
                .font(.title2.weight(.bold))
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text("Started \(prompt.session.startedAt, format: .dateTime.hour().minute()) on the \(side.title.lowercased()) · running \(DurationText.short(prompt.session.span(at: context.date)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if prompt.reason != .longRunning {
                Text("Your iPhone's clock changed during this feed, so the times may be off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch prompt.reason {
        case .longRunning: String(localized: "Were you still feeding?")
        case .clockChanged, .futureStart: String(localized: "Check this feed's times")
        }
    }

    private var endAtOption: some View {
        let lower = prompt.session.startedAt
        let upper = max(Date(), lower)
        return Card {
            VStack(alignment: .leading, spacing: NBSpacing.m) {
                DatePicker("Ended at", selection: $endTime, in: lower...upper, displayedComponents: [.hourAndMinute])
                    .font(.headline)
                Button {
                    model.recoveryEnd(at: endTime)
                } label: {
                    Text("End at \(endTime, format: .dateTime.hour().minute())")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
                .tint(NBColor.accent)
            }
        }
    }

    @ViewBuilder
    private func optionButton(_ title: String, systemImage: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
        }
        Group {
            if prominent {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
        .tint(NBColor.accent)
    }
}

#Preview("Forgotten timer") {
    let controller = PreviewSessionController.recoveryFixture()
    let model = FeedingSessionUIModel(controller: controller)
    return Color.clear.sheet(isPresented: .constant(true)) {
        RecoverySheet(prompt: controller.recoveryPrompt!, model: model)
    }
}
