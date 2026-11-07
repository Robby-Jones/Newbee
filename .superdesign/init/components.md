# Shared UI components

> Project: Newbee — native iOS 17+ app (SwiftUI, SwiftData, ActivityKit). NOT a web app: no React/Tailwind/CSS. Designs are iPhone screens (390×844 pt) and Live Activity surfaces. UI uses SF Pro / SF Pro Rounded, SF Symbols, system materials.

Framework: SwiftUI (custom components, no third-party UI library). Styling: design tokens in `NBColor`/`NBSpacing`/`NBRadius`/`NBFont` (see theme.md).

- `Card` — soft rounded card surface (radius 20, white/#1B1B20, light shadow / dark hairline)
- `SideButton` — big LEFT/RIGHT timer control (≥160pt tall), modes start/active/switchTo/resumeHere
- `SideBadge` — 'L'/'R' letter in a side-colored circle
- `SegmentBar` — horizontal L/R proportion bar
- `TimerText` — big rounded monospaced timer numerals
- `ActiveSessionPill` — floating capsule above the tab bar while a feed runs
- `UndoToastView` — capsule toast with Undo
- `FeedRow` (in FeedFormatting.swift) — History timeline row: time column, colored rail, icon+title, L/R bar, note preview, gap label

### `Newbee/Shared/Components/Card.swift`

```swift
import NewbeeShared
import SwiftUI

/// Soft rounded card: the basic surface of the app (docs/UX_SPEC.md §2).
/// Light mode gets a soft shadow; dark mode gets a hairline border instead.
struct Card<Content: View>: View {
    var padding: CGFloat = NBSpacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nbCardBackground()
    }
}

extension View {
    /// The card surface without padding, for custom layouts.
    func nbCardBackground(cornerRadius: CGFloat = NBRadius.card) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

private struct CardBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(NBColor.card, in: shape)
            .overlay {
                if colorScheme == .dark {
                    shape.strokeBorder(NBColor.hairline, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 4, y: 2)
    }
}

#Preview {
    VStack {
        Card {
            Text("Last feed").font(.headline)
            Text("2 h 14 min ago").foregroundStyle(.secondary)
        }
    }
    .padding()
    .background(NBColor.canvas)
}
```

### `Newbee/Shared/Components/SideButton.swift`

```swift
import NewbeeKit
import NewbeeShared
import SwiftUI

/// One of the two big LEFT / RIGHT controls on the timer screen (docs/UX_SPEC.md §3.3).
/// At least 160 pt tall so it can be hit with a thumb in the dark.
struct SideButton: View {
    enum Mode: Equatable {
        /// No session yet. The suggested side is pre-tinted and tagged.
        case start(suggested: Bool)
        /// This side is running.
        case active
        /// The other side is running; tapping switches here.
        case switchTo
        /// The session is paused; tapping resumes on this side.
        case resumeHere(wasLast: Bool)
    }

    let side: Side
    let mode: Mode
    /// Time on this side so far; `nil` before the session starts.
    let elapsed: TimeInterval?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: NBSpacing.s) {
                HStack(spacing: NBSpacing.s) {
                    SideBadge(side: side, style: isFilled ? .onTint : .soft)
                    Text(side.title)
                        .font(.headline)
                }
                if let elapsed {
                    TimerText(elapsed, size: 34, relativeTo: .title)
                } else {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .padding(.vertical, NBSpacing.xs)
                }
                caption
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isFilled ? NBColor.onSide : Color.primary)
            .padding(NBSpacing.l)
            .frame(maxWidth: .infinity, minHeight: NBLayout.sideButtonMinHeight)
            .background(background)
            .contentShape(.rect(cornerRadius: NBRadius.card))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(String(localized: "\(side.title) side"))
        .accessibilityIdentifier("sideButton.\(side.rawValue)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(mode == .active ? .isSelected : [])
    }

    private var isFilled: Bool {
        switch mode {
        case .active, .start(suggested: true): true
        default: false
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch mode {
        case .start(let suggested):
            Text(suggested ? LocalizedStringKey("Suggested") : LocalizedStringKey("Start"))
        case .active:
            HStack(spacing: NBSpacing.xs) {
                LiveDot(color: NBColor.onSide)
                Text("Active")
            }
        case .switchTo:
            Text("Tap to switch").foregroundStyle(.secondary)
        case .resumeHere:
            Text("Resume here").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var background: some View {
        let tint = NBColor.side(side)
        let shape = RoundedRectangle(cornerRadius: NBRadius.card, style: .continuous)
        switch mode {
        case .active:
            shape.fill(tint)
        case .start(suggested: true):
            shape.fill(tint.opacity(0.85))
        case .resumeHere(wasLast: true):
            shape.fill(NBColor.card).overlay { shape.strokeBorder(tint, lineWidth: 3) }
        default:
            shape.fill(NBColor.card).overlay { shape.strokeBorder(tint.opacity(0.6), lineWidth: 2) }
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        switch mode {
        case .start(let suggested): if suggested { parts.append(String(localized: "suggested")) }
        case .active: parts.append(String(localized: "active"))
        case .switchTo: break
        case .resumeHere: parts.append(String(localized: "paused"))
        }
        if let elapsed { parts.append(DurationText.spoken(elapsed)) }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        switch mode {
        case .start: String(localized: "Starts a feed on the \(side.title.lowercased()) side")
        case .active: ""
        case .switchTo: String(localized: "Switches to the \(side.title.lowercased()) side")
        case .resumeHere: String(localized: "Resumes on the \(side.title.lowercased()) side")
        }
    }
}

/// Slight shrink on press, without changing colors.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Modes") {
    ScrollView {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SideButton(side: .left, mode: .start(suggested: false), elapsed: nil) {}
                SideButton(side: .right, mode: .start(suggested: true), elapsed: nil) {}
            }
            HStack(spacing: 12) {
                SideButton(side: .left, mode: .active, elapsed: 725) {}
                SideButton(side: .right, mode: .switchTo, elapsed: 397) {}
            }
            HStack(spacing: 12) {
                SideButton(side: .left, mode: .resumeHere(wasLast: true), elapsed: 725) {}
                SideButton(side: .right, mode: .resumeHere(wasLast: false), elapsed: 397) {}
            }
        }
        .padding()
    }
    .background(NBColor.canvas)
}
```

### `Newbee/Shared/Components/SideBadge.swift`

```swift
import NewbeeKit
import NewbeeShared
import SwiftUI

/// A side's letter in its tint. Color is never the only signal, so the letter is always shown.
struct SideBadge: View {
    enum Style {
        /// Solid side tint with dark letter.
        case filled
        /// Light tint wash with tinted letter, for neutral backgrounds.
        case soft
        /// For use on top of a filled side-tinted surface.
        case onTint
    }

    let side: Side
    var style: Style = .filled
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 28

    var body: some View {
        Text(side.shortLabel)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .accessibilityElement()
            .accessibilityLabel(side.title)
    }

    private var foreground: Color {
        switch style {
        case .filled, .onTint: NBColor.onSide
        case .soft: NBColor.side(side)
        }
    }

    private var fill: Color {
        switch style {
        case .filled: NBColor.side(side)
        case .soft: NBColor.side(side).opacity(0.18)
        case .onTint: NBColor.onSide.opacity(0.12)
        }
    }
}

/// A small "live" dot. Pulses while a session runs, static under Reduce Motion.
struct LiveDot: View {
    var color: Color
    var isLive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8))
            .foregroundStyle(color)
            .symbolEffect(.pulse, options: .repeating, isActive: isLive && !reduceMotion)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        SideBadge(side: .left)
        SideBadge(side: .right)
        SideBadge(side: .left, style: .soft)
        SideBadge(side: .right, style: .soft)
        LiveDot(color: NBColor.left)
    }
    .padding()
}
```

### `Newbee/Shared/Components/SegmentBar.swift`

```swift
import NewbeeKit
import NewbeeShared
import SwiftUI

/// Horizontal bar showing the left/right split of a breastfeeding session.
struct SegmentBar: View {
    let left: TimeInterval
    let right: TimeInterval
    var height: CGFloat = 8

    var body: some View {
        let total = max(left + right, 0)
        GeometryReader { proxy in
            let gap: CGFloat = (left > 0 && right > 0) ? 2 : 0
            let available = max(0, proxy.size.width - gap)
            let leftWidth = total > 0 ? available * left / total : 0
            HStack(spacing: gap) {
                if left > 0 {
                    Capsule().fill(NBColor.left).frame(width: leftWidth)
                }
                if right > 0 {
                    Capsule().fill(NBColor.right)
                }
                if total == 0 {
                    Capsule().fill(Color.secondary.opacity(0.2))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Left \(DurationText.spoken(left)), right \(DurationText.spoken(right))"))
    }
}

#Preview {
    VStack(spacing: 12) {
        SegmentBar(left: 12 * 60, right: 9 * 60)
        SegmentBar(left: 20 * 60, right: 0)
        SegmentBar(left: 0, right: 0)
    }
    .padding()
}
```

### `Newbee/Shared/Components/TimerText.swift`

```swift
import NewbeeShared
import SwiftUI

/// Large stopwatch numerals: rounded, monospaced digits, scaling with Dynamic Type.
/// The value is always derived from timestamps by the caller; this view only formats it.
struct TimerText: View {
    let duration: TimeInterval
    @ScaledMetric private var size: CGFloat

    init(_ duration: TimeInterval, size: CGFloat = 64, relativeTo textStyle: Font.TextStyle = .largeTitle) {
        self.duration = duration
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        Text(DurationText.clock(duration))
            .font(NBFont.timer(size: size))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(DurationText.spoken(duration))
    }
}

#Preview {
    VStack {
        TimerText(18 * 60 + 42)
        TimerText(12 * 60 + 5, size: 34, relativeTo: .title)
        TimerText(3_723, size: 17, relativeTo: .body)
    }
}
```

### `Newbee/Shared/Components/ActiveSessionPill.swift`

```swift
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
                    .foregroundStyle(.secondary)
            } else {
                LiveDot(color: NBColor.side(side))
            }
            SideBadge(side: side, style: isPaused ? .soft : .filled)
            Text(DurationText.clock(sideTime))
                .font(.system(.headline, design: .rounded).monospacedDigit())
            Text(isPaused ? "Paused" : "Total")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(DurationText.clock(total))
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
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
```

### `Newbee/Shared/Components/UndoToastView.swift`

```swift
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
```

### `Newbee/Shared/DesignSystem/DurationText.swift`

```swift
import Foundation

/// Formats derived durations for display. Durations always come from `SessionSnapshot`.
enum DurationText {
    /// Stopwatch style: "0:07", "12:05", "1:02:03".
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%ld:%02ld:%02ld", hours, minutes, seconds)
        }
        return String(format: "%ld:%02ld", minutes, seconds)
    }

    /// Compact summary: "<1 min", "21 min", "1 h", "1 h 5 min".
    static func short(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        if minutes < 1 { return String(localized: "<1 min") }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        if rest == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(rest) min")
    }

    /// VoiceOver, minute granularity so it isn't re-announced every second: "12 minutes".
    static func spoken(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        if minutes < 1 { return String(localized: "less than a minute") }
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
```

### `Newbee/Features/History/FeedFormatting.swift`

```swift
import Foundation
import NewbeeKit
import NewbeeShared
import SwiftUI

/// Display text for feeds, shared by History and Home.
enum FeedText {
    /// "90 mL" or "3 oz", in the unit the parent entered.
    static func volume(ml: Double, unit: VolumeUnit = .milliliters) -> String {
        let value = unit.fromMilliliters(ml)
        let digits = unit == .milliliters ? 0 : 1
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(unit.symbol)"
    }

    static func contents(_ contents: BottleContents) -> String {
        switch contents {
        case .breastMilk: String(localized: "breast milk")
        case .formula: String(localized: "formula")
        case .other: String(localized: "other")
        }
    }

    /// "Breast · 21 min" or "Bottle · 90 mL formula".
    static func title(_ entry: FeedEntry) -> String {
        switch entry.details {
        case .breast:
            String(localized: "Breast · \(DurationText.short(entry.breastDuration))")
        case .bottle(let bottle):
            String(localized: "Bottle · \(volume(ml: bottle.amountML, unit: bottle.enteredUnit)) \(contents(bottle.contents))")
        }
    }

    /// "L 12 min · R 9 min", for breastfeeds only.
    static func sides(_ entry: FeedEntry) -> String? {
        guard case let .breast(left, right, _, _) = entry.details else { return nil }
        return "L \(DurationText.short(left)) · R \(DurationText.short(right))"
    }

    /// "Today", "Yesterday" or "Tue 4 Nov".
    static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "2 h 14 min ago", or "Just now" under a minute.
    static func ago(_ interval: TimeInterval) -> String {
        interval < 60 ? String(localized: "Just now") : String(localized: "\(DurationText.short(interval)) ago")
    }
}

extension FeedEntry {
    /// Tint for the row rail and icon.
    var tint: Color {
        switch details {
        case .breast(_, _, _, let last): last.map(NBColor.side) ?? NBColor.left
        case .bottle(let bottle): bottle.contents == .formula ? NBColor.bottleFormula : NBColor.bottleBreastMilk
        }
    }

    var symbolName: String {
        switch details {
        case .breast: "heart.fill"
        case .bottle: "waterbottle.fill"
        }
    }
}

/// One feed in History: time, colored rail, title, L/R split, note, gap to the previous feed.
struct FeedRow: View {
    let row: TimelineRow

    private var entry: FeedEntry { row.entry }

    var body: some View {
        HStack(alignment: .top, spacing: NBSpacing.m) {
            Text(entry.start, format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)

            Capsule()
                .fill(entry.tint)
                .frame(width: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                HStack(spacing: NBSpacing.s) {
                    Image(systemName: entry.symbolName)
                        .foregroundStyle(entry.tint)
                        .accessibilityHidden(true)
                    Text(FeedText.title(entry))
                        .font(.body.weight(.semibold))
                    if entry.needsReview {
                        ReviewBadge()
                    }
                }
                if case let .breast(left, right, _, _) = entry.details {
                    SegmentBar(left: left, right: right, height: 6)
                    if let sides = FeedText.sides(entry) {
                        Text(sides)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let gap = row.sincePrevious {
                    Label(String(localized: "\(DurationText.short(gap)) after the previous feed"), systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NBSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Small amber "Review" badge for feeds whose times were estimated.
struct ReviewBadge: View {
    var body: some View {
        Text("Review")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2), in: .capsule)
            .foregroundStyle(Color.orange)
            .accessibilityLabel("Needs review")
    }
}
```
