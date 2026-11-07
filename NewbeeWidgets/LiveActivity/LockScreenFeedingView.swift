import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

/// Lock Screen and banner presentation (docs/LIVE_ACTIVITIES.md §3.1).
///
/// ```
/// 🍼 Feeding · Left                       Paused
///   18:42                     L  12:05  (running side bold)
///   total                     R   6:37
///  [ L ] [ R ]          [ ⏸ Pause ]        [■]
/// ```
struct LockScreenFeedingView: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NBSpacing.m) {
            header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    TotalTimerText(state: state)
                        .font(NBFont.timer(size: 40))
                        .foregroundStyle(state.status == .active ? Color.primary : Color.secondary)
                    Text(state.status == .ended ? "total feed" : "total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: NBSpacing.m)
                VStack(alignment: .trailing, spacing: NBSpacing.xs) {
                    SideRow(state: state, side: .left)
                    SideRow(state: state, side: .right)
                }
            }
            if state.status == .ended {
                endedFooter
            } else {
                controls
            }
        }
        .padding(NBSpacing.l)
    }

    private var title: String {
        attributes.babyName.isEmpty ? "Feeding" : "Feeding \(attributes.babyName)"
    }

    private var header: some View {
        HStack(spacing: NBSpacing.s) {
            Image(systemName: state.status == .ended ? "checkmark.circle.fill" : "drop.fill")
                .foregroundStyle(NBColor.side(state.currentSide))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(state.statusLine(isStale: isStale))
                .font(.subheadline)
                .foregroundStyle(state.status == .paused || isStale ? NBColor.accent : Color.secondary)
                .lineLimit(1)
                .invalidatableContent()
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: NBSpacing.s) {
            SideSwitchButton(sessionID: attributes.sessionID, state: state, side: .left)
            SideSwitchButton(sessionID: attributes.sessionID, state: state, side: .right)
            Spacer(minLength: NBSpacing.s)
            PauseResumeButton(sessionID: attributes.sessionID, state: state)
            Spacer(minLength: NBSpacing.l)
            EndButton(sessionID: attributes.sessionID)
        }
    }

    @ViewBuilder
    private var endedFooter: some View {
        if let endedAt = state.pausedAt {
            Text("Started \(state.sessionStart, style: .time) · ended \(endedAt, style: .time)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
