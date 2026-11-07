import NewbeeKit
import NewbeeShared
import SwiftUI

/// Shown in the timer cover right after a feed ends: "21 min · L 12 · R 9" (docs/UX_SPEC.md §3.3).
/// Undo is offered by the toast underneath.
struct SessionSummaryView: View {
    let session: SessionSnapshot
    let onDone: () -> Void

    var body: some View {
        let end = session.endedAt ?? session.segments.last?.end ?? session.startedAt
        let left = session.duration(on: .left, at: end)
        let right = session.duration(on: .right, at: end)
        let total = session.feedingDuration(at: end)

        VStack(spacing: NBSpacing.xl) {
            Spacer(minLength: 0)
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
            Spacer(minLength: 0)
            Button(action: onDone) {
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
    SessionSummaryView(session: PreviewSessionController.completedFixture(endingBefore: .now)) {}
        .background(NBColor.canvas)
}
