import NewbeeKit
import NewbeeShared
import SwiftUI
import WidgetKit

typealias FeedingState = FeedingActivityAttributes.ContentState

extension Side {
    var displayName: String { self == .left ? "Left" : "Right" }
}

extension FeedingState {
    /// One-line status, e.g. "Feeding on left", "Paused", "Since last feed".
    func statusLine(isStale: Bool) -> String {
        if isStale && status != .ended { return "Still feeding? Open Newbee" }
        switch status {
        case .active: return "Feeding on \(currentSide.displayName.lowercased())"
        case .paused: return "Paused"
        case .ended: return "Since last feed"
        }
    }

    /// The side to offer for the next feed: the other side from the one the last feed ended on,
    /// as the app suggests.
    var suggestedNextSide: Side { currentSide.opposite }
}

/// Text colors for the Live Activity.
///
/// Never the system's `.primary` / `.secondary` here: on the Lock Screen those were drawn for
/// a different appearance from the activity's background (white text on the white card in light
/// mode, black on the dark card at night), which hid the big number. These adapt the same way as
/// `NBColor.card`, so text and background always match. Values meet WCAG AA on the card.
enum ActivityColor {
    static let primaryText = Color(light: 0x1B1B20, dark: 0xF5F5F7)
    static let secondaryText = Color(light: 0x66666C, dark: 0xA1A1AA)

    /// A side's color for text and icons on a light tint of it (the side colors themselves are
    /// too pale for text on white).
    static func sideInk(_ side: Side) -> Color {
        side == .left ? Color(light: 0x5B4BB8, dark: 0xC3B8F5) : Color(light: 0x1F7A70, dark: 0x7FD8CD)
    }

    static let accentInk = Color(light: 0x4A4EC2, dark: 0xA5A8F5)
    static let destructiveInk = Color(light: 0xB43A50, dark: 0xF0A0AE)

    /// The Lock Screen background for the app's appearance setting. A fixed color when the app
    /// forces light or dark (the view also gets that color scheme), else the adaptive card.
    static func background(_ appearance: LiveActivityAppearance?) -> Color {
        switch appearance {
        case .some(.light): Color(red: 1, green: 1, blue: 1)
        case .some(.dark): Color(red: 0x1B / 255, green: 0x1B / 255, blue: 0x20 / 255)
        case .some(.system), .none: NBColor.card
        }
    }
}

extension LiveActivityAppearance {
    /// The color scheme to force, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    /// Draws the view in the app's chosen appearance (`nil` or `.system` follows the system).
    @ViewBuilder
    func activityAppearance(_ appearance: LiveActivityAppearance?) -> some View {
        if let scheme = appearance?.colorScheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}

/// "L" / "R" in a side-colored circle. Color is never the only signal.
struct SideBadge: View {
    let side: Side
    var size: CGFloat = 28
    /// Hollow when the side isn't running (paused or ended).
    var filled: Bool = true

    var body: some View {
        Text(side.shortLabel)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? Color.white : NBColor.side(side))
            .frame(width: size, height: size)
            .background {
                if filled {
                    Circle().fill(NBColor.side(side))
                } else {
                    Circle().strokeBorder(NBColor.side(side), lineWidth: 2)
                }
            }
            .accessibilityLabel("\(side.displayName) side")
    }
}

/// Total feeding time (pauses excluded). Ticks via the system while active; frozen otherwise.
struct TotalTimerText: View {
    let state: FeedingState

    var body: some View {
        if state.status == .active, let start = state.runningTotalTimerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .accessibilityLabel(Text("Total feeding time"))
                .accessibilityValue(Text(timerInterval: start...Date.distantFuture, countsDown: false))
        } else {
            Text(LiveActivityFormat.clock(state.totalAccumulated))
                .monospacedDigit()
                .accessibilityLabel("Total feeding time")
                .accessibilityValue(LiveActivityFormat.spoken(state.totalAccumulated))
        }
    }
}

/// The line about the feed the count runs from: "Last feed L 12:05 · R 9:00 · ended 3:40 PM",
/// or "Last feed bottle 90 mL · ended 3:40 PM" ("at" for a bottle with no duration). With
/// Settings' "Count from" at the start, it names the time the count runs from: "started 3:20 PM".
struct LastFeedLine: View {
    let state: FeedingState

    var body: some View {
        if let endedAt = state.lastFeedEndedAt {
            // A bottle with no duration ended when it started.
            let fromStart = state.countFrom == .start
            let when = endedAt <= state.sessionStart
                ? String(localized: "at") : fromStart ? String(localized: "started") : String(localized: "ended")
            let time = fromStart ? state.sessionStart : endedAt
            if let bottle = state.lastBottle {
                line(Text("Last feed bottle \(bottle.formatted) · \(when) \(time, style: .time)"))
                    .accessibilityLabel(
                        "Last feed: bottle, \(bottle.formatted), \(when) \(time.formatted(date: .omitted, time: .shortened))"
                    )
            } else {
                let left = LiveActivityFormat.clock(state.leftAccumulated)
                let right = LiveActivityFormat.clock(state.rightAccumulated)
                line(Text("Last feed L \(left) · R \(right) · \(when) \(time, style: .time)"))
                    .accessibilityLabel(
                        "Last feed: left \(LiveActivityFormat.spoken(state.leftAccumulated)), right \(LiveActivityFormat.spoken(state.rightAccumulated)), \(when) \(time.formatted(date: .omitted, time: .shortened))"
                    )
            }
        }
    }

    private func line(_ text: Text) -> some View {
        text
            .font(.footnote)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The big number: the feed's total while it runs or is paused, the time since the last feed after.
struct HeadlineTimerText: View {
    let state: FeedingState
    let isStale: Bool

    var body: some View {
        if let since = state.sinceLastFeedStart {
            SinceLastFeedText(since: since)
        } else {
            TotalTimerText(state: state)
        }
    }
}

/// Time on one side. Ticks only for the running side.
struct SideTimerText: View {
    let state: FeedingState
    let side: Side

    var body: some View {
        if state.isRunning(side), let start = state.runningSideTimerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        } else {
            Text(LiveActivityFormat.clock(state.accumulated(on: side)))
                .monospacedDigit()
        }
    }
}

/// Dark text on a filled side color: white would fall below WCAG AA on the light side tints.
private let textOnSide = Color(light: 0x1B1B20, dark: 0x0F0F12)

/// "Feeding", "Paused" or "Since last feed" with a small glyph: one quiet line instead of a badge
/// and a status label.
struct ActivityStatusLabel: View {
    let state: FeedingState
    let isStale: Bool
    var textColor: Color = ActivityColor.secondaryText

    var body: some View {
        HStack(spacing: NBSpacing.xs) {
            Text(text)
                .lineLimit(1)
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(symbolColor)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(textColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.statusLine(isStale: isStale))
    }

    private var showsStale: Bool { isStale && state.status != .ended }

    private var text: String {
        if showsStale { return "Still feeding?" }
        switch state.status {
        case .active: return "Feeding"
        case .paused: return "Paused"
        case .ended: return "Since last feed"
        }
    }

    private var symbol: String {
        if showsStale { return "questionmark.circle" }
        switch state.status {
        case .active: return "drop.fill"
        case .paused: return "pause.fill"
        case .ended: return "clock"
        }
    }

    private var symbolColor: Color {
        state.status == .active && !showsStale ? NBColor.side(state.currentSide) : textColor
    }
}

/// One side's time as a pill: "L 12:05". The running side is filled with its color.
///
/// While a feed is open, the pill is the side-switch control: tapping the other side switches to
/// it, or resumes on it when paused. Tapping the running side changes nothing, because the
/// intent targets a state rather than toggling.
struct SidePill: View {
    let sessionID: UUID
    let state: FeedingState
    let side: Side

    var body: some View {
        Button(intent: SwitchFeedingSideIntent(sessionID: sessionID, side: side)) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var label: some View {
        let running = state.isRunning(side)
        let pausedHere = state.status == .paused && state.currentSide == side
        let tint = NBColor.side(side)
        return HStack(spacing: NBSpacing.s) {
            Text(side.shortLabel)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            SideTimerText(state: state, side: side)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                // Timer text otherwise claims all available width.
                .frame(maxWidth: 72)
        }
        .foregroundStyle(running ? textOnSide : ActivityColor.sideInk(side))
        .padding(.horizontal, NBSpacing.m)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Capsule().fill(running ? tint : tint.opacity(pausedHere ? 0.3 : 0.16)))
        .contentShape(Capsule())
    }

    private var accessibilityLabel: String {
        if state.isRunning(side) { return "Feeding on \(side.displayName.lowercased())" }
        if state.status == .paused { return "Resume on \(side.displayName.lowercased())" }
        return "Switch to \(side.displayName.lowercased())"
    }

    private var accessibilityValue: Text {
        if state.isRunning(side), let start = state.runningSideTimerStart {
            return Text(timerInterval: start...Date.distantFuture, countsDown: false)
        }
        return Text(LiveActivityFormat.spoken(state.accumulated(on: side)))
    }
}

/// The round "+" shown once a feed has ended: opens the app on Home to log the next feed. One
/// quiet control, so the time since the last feed stays the focus.
struct NewFeedButton: View {
    var size: CGFloat = 52

    var body: some View {
        Link(destination: NewbeeLink.home) {
            Image(systemName: "plus")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(ActivityColor.accentInk))
                .contentShape(Circle())
        }
        .accessibilityLabel("Open Newbee to start a feed")
    }
}

/// A round 44 pt icon control on a soft tint of its color.
struct ActivityCircleLabel: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Circle().fill(tint.opacity(0.18)))
            .contentShape(Circle())
    }
}

/// Pause or resume, whichever applies. Resume continues on the side that was running.
struct PauseResumeButton: View {
    let sessionID: UUID
    let state: FeedingState

    var body: some View {
        if state.status == .paused {
            Button(intent: ResumeFeedingIntent(sessionID: sessionID)) {
                ActivityCircleLabel(systemImage: "play.fill", tint: ActivityColor.sideInk(state.currentSide))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume on \(state.currentSide.displayName.lowercased())")
        } else {
            Button(intent: PauseFeedingIntent(sessionID: sessionID)) {
                ActivityCircleLabel(systemImage: "pause.fill", tint: ActivityColor.accentInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause feeding")
        }
    }
}

/// End is the only control in the destructive color, and sits last with extra space before it
/// so it isn't hit by accident.
struct EndButton: View {
    let sessionID: UUID

    var body: some View {
        Button(intent: EndFeedingIntent(sessionID: sessionID)) {
            ActivityCircleLabel(systemImage: "stop.fill", tint: ActivityColor.destructiveInk)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End feeding")
    }
}

/// The side pills and the controls while a feed is open, shared by the Lock Screen and the
/// expanded Dynamic Island so both read the same way.
///
/// ```
///  [ L 12:05 ] [ R 6:37 ]  (⏸)  (■)
/// ```
struct ActivitySidesAndControls: View {
    let attributes: FeedingActivityAttributes
    let state: FeedingState

    var body: some View {
        // The content's session: it differs from the attributes' when the activity was carried
        // over to another feed.
        let sessionID = LiveActivityRecord.sessionID(attributes: attributes, state: state)
        HStack(spacing: NBSpacing.s) {
            SidePill(sessionID: sessionID, state: state, side: .left)
            SidePill(sessionID: sessionID, state: state, side: .right)
            PauseResumeButton(sessionID: sessionID, state: state)
            EndButton(sessionID: sessionID)
                .padding(.leading, NBSpacing.xs)
        }
    }
}
