// Compiled into both the app and the widget extension, so the app can draw the exact view the
// Live Activity shows for review screenshots (`LiveActivityReviewGallery`).

import NewbeeKit
import NewbeeShared
import SwiftUI
import UIKit

/// The Live Activity's colors: fixed values for one card color, never adaptive ones or the
/// system's `.primary` / `.secondary` (those were drawn for the wrong appearance on the Lock
/// Screen before). Text meets WCAG AA on the card.
///
/// The Dynamic Island is always `night` (black). The Lock Screen card is `night` in the standard
/// theme, or a soft tint of the theme's color otherwise (`ContentState.theme`). Views read the palette from the environment
/// (`\.activityPalette`, `night` unless set).
struct ActivityPalette: Sendable {
    var background: Color
    /// The appearance the card reads as, so adaptive side colors pick the matching values.
    var colorScheme: ColorScheme
    var primaryText: Color
    var secondaryText: Color
    /// The round "+" (the theme's accent), with `onFill` on it.
    var newFeed: Color
    /// Dark glyphs on the light fills: the "+", the feed icon.
    var onFill: Color
    /// The initial's circle when there's no photo, with the bee's ink for the letter.
    var avatar: Color
    var onAvatar: Color
    /// Bottle icon fill (`NBColor.bottleBreastMilk`).
    var bottle: Color
    /// Feed icon fills for a breastfeed that ended on each side.
    var leftFill: Color
    var rightFill: Color
    /// A side's color for text and icons on a soft tint of it.
    var leftInk: Color
    var rightInk: Color
    /// Pause.
    var accentInk: Color
    /// End.
    var destructiveInk: Color

    func sideInk(_ side: Side) -> Color {
        side == .left ? leftInk : rightInk
    }

    func sideFill(_ side: Side) -> Color {
        side == .left ? leftFill : rightFill
    }

    /// The Lock Screen card for a theme.
    static func lockScreen(_ theme: NBTheme?) -> ActivityPalette {
        switch theme ?? .standard {
        case .standard: .night
        case .pink: .blush
        // Ratios for each card are in docs/UX_SPEC.md §2.1; all text is at least 5.2:1 on it.
        case .sage: .tinted(background: 0xE3EFE3, primaryText: 0x17251A, secondaryText: 0x4D5F50, newFeed: 0x8CC79A, accentInk: 0x3E6848)
        case .ocean: .tinted(background: 0xDFEBF6, primaryText: 0x142230, secondaryText: 0x4A5B6B, newFeed: 0x7FB4E3, accentInk: 0x275A82)
        case .lavender: .tinted(background: 0xECE5F8, primaryText: 0x221A33, secondaryText: 0x5A4E6E, newFeed: 0xB49CEB, accentInk: 0x5C449E)
        case .peach: .tinted(background: 0xFCE6D8, primaryText: 0x2E1A10, secondaryText: 0x6B4E3E, newFeed: 0xF2A57A, accentInk: 0x93461C)
        }
    }

    /// A light card in a theme's color, otherwise the same as `blush`: the side, bottle and End
    /// colors stay put, and pass AA on every tinted card.
    static func tinted(background: UInt32, primaryText: UInt32, secondaryText: UInt32, newFeed: UInt32, accentInk: UInt32) -> ActivityPalette {
        var palette = blush
        palette.background = Color(rgb: background)
        palette.primaryText = Color(rgb: primaryText)
        palette.secondaryText = Color(rgb: secondaryText)
        palette.newFeed = Color(rgb: newFeed)
        palette.accentInk = Color(rgb: accentInk)
        return palette
    }

    /// Black card, white text: the standard theme and the Dynamic Island.
    static let night = ActivityPalette(
        background: .black,
        colorScheme: .dark,
        primaryText: .white,
        // #B8B8BE, 10:1 on black.
        secondaryText: Color(rgb: 0xB8B8BE),
        // The standard accent in dark mode (`NBColor.accent`).
        newFeed: Color(rgb: 0x8E91F0),
        onFill: Color(rgb: 0x14141A),
        avatar: Color(rgb: 0xF29DB8),
        onAvatar: Color(rgb: 0x3B2F4A),
        bottle: Color(rgb: 0xF5B593),
        leftFill: Color(rgb: 0xB3A6F0),
        rightFill: Color(rgb: 0x6FCFC4),
        leftInk: Color(rgb: 0xC3B8F5),
        rightInk: Color(rgb: 0x7FD8CD),
        accentInk: Color(rgb: 0xA5A8F5),
        destructiveInk: Color(rgb: 0xF0A0AE)
    )

    /// Soft blush card, dark plum text: the pink theme's Lock Screen. Ratios are on #FBE1EA.
    static let blush = ActivityPalette(
        background: Color(rgb: 0xFBE1EA),
        colorScheme: .light,
        // 13.7:1.
        primaryText: Color(rgb: 0x2A1720),
        // 6.1:1.
        secondaryText: Color(rgb: 0x6E4B5A),
        // A rose pastel; the dark "+" on it is 7:1.
        newFeed: Color(rgb: 0xE87FA6),
        onFill: Color(rgb: 0x14141A),
        // White, so the initial's circle stands out from the blush card.
        avatar: .white,
        onAvatar: Color(rgb: 0x3B2F4A),
        bottle: Color(rgb: 0xF2A37B),
        leftFill: Color(rgb: 0x9C8CE0),
        rightFill: Color(rgb: 0x4FB3A9),
        // 5.3:1 and 5.2:1, and above 4.5:1 on their soft tints too.
        leftInk: Color(rgb: 0x5E4CB8),
        rightInk: Color(rgb: 0x24696A),
        // 5.3:1.
        accentInk: Color(rgb: 0xA3335F),
        // 5.2:1.
        destructiveInk: Color(rgb: 0xAE2F4B)
    )
}

private struct ActivityPaletteKey: EnvironmentKey {
    static let defaultValue = ActivityPalette.night
}

extension EnvironmentValues {
    /// The Live Activity palette the views below draw with (`ActivityPalette`).
    var activityPalette: ActivityPalette {
        get { self[ActivityPaletteKey.self] }
        set { self[ActivityPaletteKey.self] = newValue }
    }
}

/// Sizes for the since-last-feed layout on the Lock Screen and in the expanded Dynamic Island.
struct SinceLastFeedActivityStyle {
    var avatarSize: CGFloat
    var newFeedSize: CGFloat
    var relativeSize: CGFloat
    var headlineSize: CGFloat
    var detailSize: CGFloat
    var showsName: Bool

    static let lockScreen = SinceLastFeedActivityStyle(
        avatarSize: 60, newFeedSize: 60, relativeSize: 17, headlineSize: 27, detailSize: 17, showsName: true
    )

    /// The island's bottom region is shorter, so everything is a little smaller.
    static let island = SinceLastFeedActivityStyle(
        avatarSize: 48, newFeedSize: 48, relativeSize: 15, headlineSize: 22, detailSize: 15, showsName: true
    )
}

/// After a feed ends: who, how long ago, when, what, and a "+" for the next one.
///
/// ```
///   (photo)🐝      28 min, 30 sec ago
///                Last fed: 10:33 PM          (+)
///    Millie         (🍼) 1 oz
/// ```
///
/// The first line is a live relative date the system ticks ("28 min, 30 sec", then "1 hr, 5 min"
/// past an hour), so the app never pushes updates for it. "Last fed" is the time the count runs
/// from (Settings' "Count from": the feed's start or end).
struct SinceLastFeedActivityContent: View {
    let state: FeedingActivityAttributes.ContentState
    let babyName: String
    /// Where the count runs from (`ContentState.sinceLastFeedStart`).
    let since: Date
    var style: SinceLastFeedActivityStyle = .lockScreen
    /// The baby's photo; `nil` draws the initial (or the bee with no name either).
    var photo: UIImage?
    @Environment(\.activityPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BabyAvatarColumn(name: babyName, photo: photo, size: style.avatarSize, showsName: style.showsName)
            VStack(spacing: 2) {
                Text("\(since, style: .relative) ago")
                    .font(.system(size: style.relativeSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Last fed: \(since, style: .time)")
                    .font(.system(size: style.headlineSize, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                LastFeedDetail(state: state, size: style.detailSize)
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            NewFeedButton(size: style.newFeedSize)
        }
    }

    private var accessibilityLabel: Text {
        Text("Last fed at \(since, style: .time), \(since, style: .relative) ago. \(LastFeedDetail.spoken(state))")
    }
}

/// The baby's photo (or initial) with a tiny bee on its corner, and the name underneath.
struct BabyAvatarColumn: View {
    let name: String
    let photo: UIImage?
    let size: CGFloat
    var showsName = true
    @Environment(\.activityPalette) private var palette

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 4) {
            avatar
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    // With no name and no photo the bee is the avatar itself.
                    if photo != nil || !trimmedName.isEmpty {
                        TinyBee(width: size * 0.42)
                            .offset(x: size * 0.12, y: -size * 0.1)
                    }
                }
            if showsName, !trimmedName.isEmpty {
                Text(trimmedName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: size + 16)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatar: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if let initial = trimmedName.first {
            Circle()
                .fill(palette.avatar)
                .overlay {
                    Text(String(initial).uppercased())
                        .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.onAvatar)
                }
        } else {
            Circle()
                .fill(palette.avatar)
                .overlay { TinyBee(width: size * 0.62) }
        }
    }
}

/// The feed the count runs from, as an icon in a colored circle and an amount: a bottle and
/// "90 mL", or a heart and each side's time, "L 12m · R 9m".
struct LastFeedDetail: View {
    let state: FeedingActivityAttributes.ContentState
    var size: CGFloat = 17
    @Environment(\.activityPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.lastBottle == nil ? "heart.fill" : "waterbottle.fill")
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(palette.onFill)
                .frame(width: size * 1.6, height: size * 1.6)
                .background(Circle().fill(iconFill))
            Text(Self.amount(state))
                .font(.system(size: size, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Bottle color, or the side the breastfeed ended on.
    private var iconFill: Color {
        guard state.lastBottle == nil else { return palette.bottle }
        return palette.sideFill(state.currentSide)
    }

    /// "90 mL", or "L 12m · R 9m" with any side that wasn't used left out.
    static func amount(_ state: FeedingActivityAttributes.ContentState) -> String {
        if let bottle = state.lastBottle { return bottle.formatted }
        var parts: [String] = []
        if state.leftAccumulated > 0 { parts.append("L \(LiveActivityFormat.compact(state.leftAccumulated))") }
        if state.rightAccumulated > 0 { parts.append("R \(LiveActivityFormat.compact(state.rightAccumulated))") }
        return parts.isEmpty ? LiveActivityFormat.compact(0) : parts.joined(separator: " · ")
    }

    static func spoken(_ state: FeedingActivityAttributes.ContentState) -> String {
        if let bottle = state.lastBottle { return String(localized: "Bottle, \(bottle.formatted).") }
        return String(localized: "Breastfeed, left \(LiveActivityFormat.spoken(state.leftAccumulated)), right \(LiveActivityFormat.spoken(state.rightAccumulated)).")
    }
}

/// The round "+" shown once a feed has ended: opens the app on Home to log the next feed.
struct NewFeedButton: View {
    var size: CGFloat = 60
    @Environment(\.activityPalette) private var palette

    var body: some View {
        Link(destination: NewbeeLink.home) {
            Image(systemName: "plus")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(palette.onFill)
                .frame(width: size, height: size)
                .background(Circle().fill(palette.newFeed))
                .contentShape(Circle())
        }
        .accessibilityLabel("Open Newbee to start a feed")
    }
}

/// A tiny bee from the app icon, drawn with plain shapes so the Lock Screen can render it: two
/// wings, a striped honey body, an eye. About 0.8 as tall as wide. Decorative only.
struct TinyBee: View {
    let width: CGFloat

    private static let honey = Color(red: 1, green: 0xC9 / 255, blue: 0x3C / 255)
    private static let ink = Color(red: 0x3B / 255, green: 0x2F / 255, blue: 0x4A / 255)
    private static let wing = Color(red: 0xE8 / 255, green: 0xF1 / 255, blue: 1)

    var body: some View {
        let w = width
        ZStack {
            // Wings, behind and above the body.
            Ellipse()
                .fill(Self.wing.opacity(0.95))
                .overlay(Ellipse().strokeBorder(Self.ink.opacity(0.35), lineWidth: max(w * 0.03, 0.75)))
                .frame(width: w * 0.36, height: w * 0.46)
                .rotationEffect(.degrees(-24))
                .offset(x: -w * 0.08, y: -w * 0.22)
            Ellipse()
                .fill(Self.wing.opacity(0.95))
                .overlay(Ellipse().strokeBorder(Self.ink.opacity(0.35), lineWidth: max(w * 0.03, 0.75)))
                .frame(width: w * 0.32, height: w * 0.4)
                .rotationEffect(.degrees(22))
                .offset(x: w * 0.14, y: -w * 0.2)
            // Body with two stripes.
            Ellipse()
                .fill(Self.honey)
                .frame(width: w * 0.82, height: w * 0.56)
                .overlay {
                    HStack(spacing: w * 0.09) {
                        Capsule().fill(Self.ink).frame(width: w * 0.08, height: w * 0.5)
                        Capsule().fill(Self.ink).frame(width: w * 0.08, height: w * 0.46)
                    }
                    .offset(x: -w * 0.06)
                }
                .clipShape(Ellipse())
                .overlay(alignment: .trailing) {
                    Circle().fill(Self.ink)
                        .frame(width: w * 0.08, height: w * 0.08)
                        .offset(x: -w * 0.12, y: -w * 0.04)
                }
                .offset(y: w * 0.1)
        }
        .frame(width: w, height: w * 0.8)
        .rotationEffect(.degrees(-10))
        .accessibilityHidden(true)
    }
}
