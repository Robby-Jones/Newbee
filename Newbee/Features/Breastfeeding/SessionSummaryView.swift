import NewbeeKit
import NewbeeShared
import SwiftUI

/// Shown in the timer cover right after a feed ends: "21 min · L 12 · R 9" (docs/UX_SPEC.md §3.3),
/// with room to add a note while the feed is fresh in mind. Undo is offered by the toast underneath.
struct SessionSummaryView: View {
    let session: SessionSnapshot
    /// Called with the note as typed when the parent taps Done.
    let onDone: (String) -> Void

    @State private var note: String

    init(session: SessionSnapshot, onDone: @escaping (String) -> Void) {
        self.session = session
        self.onDone = onDone
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
                            .foregroundStyle(.secondary)
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
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(String(localized: "\(side.title) side, \(DurationText.spoken(time))"))
                            }
                            if let first = session.startingSide {
                                Text("Started on the \(first.title.lowercased()). Next time, start on the \(session.lastSide?.opposite.title.lowercased() ?? first.opposite.title.lowercased()).")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
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

            Button {
                onDone(note.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
            .tint(NBColor.accent)
        }
        .padding(NBSpacing.l)
        .padding(.bottom, 56) // room for the undo toast
    }
}

#Preview {
    SessionSummaryView(session: PreviewSessionController.completedFixture(endingBefore: .now)) { _ in }
        .background(NBColor.canvas)
}
