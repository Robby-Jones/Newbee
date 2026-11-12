import NewbeeKit
import NewbeeShared
import SwiftUI

/// Shown in the timer cover right after a feed ends: "21 min · L 12 · R 9" (docs/UX_SPEC.md §3.3),
/// with room to add a note while the feed is fresh in mind. Undo, below Done, takes the parent
/// back to the timer with both sides paused, for an End tapped by mistake or too early.
struct SessionSummaryView: View {
    let session: SessionSnapshot
    /// Called with the note as typed when the parent taps Done.
    let onDone: (String) -> Void
    /// Called with the note as typed when the parent taps Undo.
    let onUndo: (String) -> Void

    @State private var note: String

    init(session: SessionSnapshot, onDone: @escaping (String) -> Void, onUndo: @escaping (String) -> Void) {
        self.session = session
        self.onDone = onDone
        self.onUndo = onUndo
        _note = State(initialValue: session.notes)
    }

    var body: some View {
        let end = session.endedAt ?? session.segments.last?.end ?? session.startedAt
        let left = session.duration(on: .left, at: end)
        let right = session.duration(on: .right, at: end)
        let total = session.feedingDuration(at: end)

        VStack(spacing: NBSpacing.l) {
            ScrollView {
                VStack(spacing: NBSpacing.xl) {
                    VStack(spacing: NBSpacing.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(NBColor.accent)
                            .accessibilityHidden(true)
                        Text("Feed saved")
                            .font(.title2.weight(.semibold))
                        Text(DurationText.short(total))
                            .font(NBFont.timer(size: 44))
                        Text("\(session.startedAt, format: .dateTime.hour().minute()) – \(end, format: .dateTime.hour().minute())")
                            .font(.subheadline)
                            .foregroundStyle(NBColor.secondaryText)
                    }
                    .padding(.top, NBSpacing.xl)
                    .accessibilityElement(children: .combine)

                    Card {
                        VStack(alignment: .leading, spacing: NBSpacing.m) {
                            SegmentBar(left: left, right: right, height: 10)
                            ForEach(Side.allCases, id: \.self) { side in
                                let time = side == .left ? left : right
                                HStack {
                                    SideBadge(side: side, style: time > 0 ? .filled : .soft)
                                    Text(side.title)
                                    Spacer()
                                    Text(DurationText.short(time))
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(NBColor.secondaryText)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(String(localized: "\(side.title) side, \(DurationText.spoken(time))"))
                            }
                            if let first = session.startingSide {
                                Text("Started on the \(first.title.lowercased()). Next time, start on the \(session.lastSide?.opposite.title.lowercased() ?? first.opposite.title.lowercased()).")
                                    .font(.footnote)
                                    .foregroundStyle(NBColor.secondaryText)
                            }
                        }
                    }

                    Card {
                        NotesEditor(text: $note, placeholder: "Add a note…", minLines: 4, fieldIdentifier: "summary.note")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: NBSpacing.s) {
                Button {
                    onDone(trimmedNote)
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
                .tint(NBColor.accent)

                Button {
                    onUndo(trimmedNote)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .tint(NBColor.accent)
                .accessibilityHint("Goes back to the feed with both sides paused")
                .accessibilityIdentifier("summary.undo")
            }
        }
        .padding(NBSpacing.l)
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    SessionSummaryView(
        session: PreviewSessionController.completedFixture(endingBefore: .now),
        onDone: { _ in },
        onUndo: { _ in }
    )
    .background(NBColor.canvas)
}
