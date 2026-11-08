import NewbeeKit
import NewbeeShared
import SwiftUI

/// Floating pill shown on every tab while a breastfeeding session is active or paused
/// (docs/UX_SPEC.md §1): "● L 12:05 · Total 18:42". Tapping it opens the timer.
struct ActiveSessionPill: View {
    let session: SessionSnapshot
    let action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            button(at: context.date)
        }
        .padding(.horizontal, NBSpacing.l)
        .padding(.bottom, NBSpacing.s)
    }

    private func button(at now: Date) -> some View {
        let side = session.lastSide ?? .left
        let isPaused = session.status == .paused
        let sideTime = session.duration(on: side, at: now)
        let total = session.feedingDuration(at: now)
        return Button(action: action) {
            content(at: now)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("activeSessionPill")
        .accessibilityLabel(String(localized: "Feeding on the \(side.title.lowercased()) side"))
        .accessibilityValue(
            isPaused
                ? String(localized: "Paused, total \(DurationText.spoken(total))")
                : String(localized: "\(DurationText.spoken(sideTime)) on this side, total \(DurationText.spoken(total))")
        )
        .accessibilityHint(String(localized: "Opens the feeding timer"))
    }

    private func content(at now: Date) -> some View {
        let side = session.lastSide ?? .left
        let isPaused = session.status == .paused
        let sideTime = session.duration(on: side, at: now)
        let total = session.feedingDuration(at: now)
        return HStack(spacing: NBSpacing.s) {
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NBColor.secondaryText)
            } else {
                LiveDot(color: NBColor.side(side))
            }
            SideBadge(side: side, style: isPaused ? .soft : .filled)
            Text(DurationText.clock(sideTime))
                .font(.system(.headline, design: .rounded).monospacedDigit())
            Text(isPaused ? "Paused" : "Total")
                .font(.subheadline)
                .foregroundStyle(NBColor.secondaryText)
            Text(DurationText.clock(total))
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(NBColor.secondaryText)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NBColor.secondaryText)
        }
        .lineLimit(1)
        .padding(.horizontal, NBSpacing.l)
        .frame(minHeight: 52)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule().strokeBorder(NBColor.side(side).opacity(isPaused ? 0.3 : 0.7), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        .saturation(isPaused ? 0.4 : 1)
    }
}

extension View {
    /// Adds the Active Session Pill above the tab bar when a session is running.
    func activeSessionPillInset(_ model: FeedingSessionUIModel?) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if let model, let session = model.activeSession, model.recoveryPrompt == nil {
                ActiveSessionPill(session: session) { model.openTimer() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

#Preview("Active and paused") {
    VStack {
        Spacer()
        ActiveSessionPill(session: PreviewSessionController.activeFixture().activeSession!) {}
        ActiveSessionPill(session: PreviewSessionController.pausedFixture().activeSession!) {}
    }
    .background(NBColor.canvas)
}
