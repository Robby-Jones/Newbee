// Compiled into both the app and the widget extension, so the app can draw the exact view the
// Live Activity shows for review screenshots (`LiveActivityReviewGallery`).

import NewbeeKit
import NewbeeShared
import SwiftUI
import UIKit

/// The Live Activity's colors. It's always dark (2026-11-19): a black card with white text,
/// whatever the phone's or the app's appearance, so these are fixed values, never adaptive ones
/// or the system's `.primary` / `.secondary` (those were drawn for the wrong appearance on the
/// Lock Screen before). Text meets WCAG AA on black.
enum ActivityPalette {
    static let background = Color.black
    static let primaryText = Color.white
    /// #B8B8BE, 10:1 on black.
    static let secondaryText = Color(red: 0xB8 / 255, green: 0xB8 / 255, blue: 0xBE / 255)
    /// Newbee's accent in dark mode (`NBColor.accent`), for the round "+".
    static let newFeed = Color(red: 0x8E / 255, green: 0x91 / 255, blue: 0xF0 / 255)
    /// Dark glyphs on the light fills above: the "+", the feed icon.
    static let onFill = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x1A / 255)
    /// The initial's circle when there's no photo: a soft rose, with the bee's ink for the letter.
    static let avatar = Color(red: 0xF2 / 255, green: 0x9D / 255, blue: 0xB8 / 255)
    static let onAvatar = Color(red: 0x3B / 255, green: 0x2F / 255, blue: 0x4A / 255)
    /// Bottle icon fill: the breast-milk bottle color in dark mode (`NBColor.bottleBreastMilk`).
    static let bottle = Color(red: 0xF5 / 255, green: 0xB5 / 255, blue: 0x93 / 255)
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BabyAvatarColumn(name: babyName, photo: photo, size: style.avatarSize, showsName: style.showsName)
            VStack(spacing: 2) {
                Text("\(since, style: .relative) ago")
                    .font(.system(size: style.relativeSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(ActivityPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Last fed: \(since, style: .time)")
                    .font(.system(size: style.headlineSize, weight: .bold, design: .rounded))
                    .foregroundStyle(ActivityPalette.primaryText)
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
                    .foregroundStyle(ActivityPalette.secondaryText)
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
                .fill(ActivityPalette.avatar)
                .overlay {
                    Text(String(initial).uppercased())
                        .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                        .foregroundStyle(ActivityPalette.onAvatar)
                }
        } else {
            Circle()
                .fill(ActivityPalette.avatar)
                .overlay { TinyBee(width: size * 0.62) }
        }
    }
}

/// The feed the count runs from, as an icon in a colored circle and an amount: a bottle and
/// "90 mL", or a heart and each side's time, "L 12m · R 9m".
struct LastFeedDetail: View {
    let state: FeedingActivityAttributes.ContentState
    var size: CGFloat = 17

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.lastBottle == nil ? "heart.fill" : "waterbottle.fill")
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(ActivityPalette.onFill)
                .frame(width: size * 1.6, height: size * 1.6)
                .background(Circle().fill(iconFill))
            Text(Self.amount(state))
                .font(.system(size: size, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(ActivityPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Bottle color, or the side the breastfeed ended on (its color in dark mode).
    private var iconFill: Color {
        guard state.lastBottle == nil else { return ActivityPalette.bottle }
        return state.currentSide == .left
            ? Color(red: 0xB3 / 255, green: 0xA6 / 255, blue: 0xF0 / 255)
            : Color(red: 0x6F / 255, green: 0xCF / 255, blue: 0xC4 / 255)
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

    var body: some View {
        Link(destination: NewbeeLink.home) {
            Image(systemName: "plus")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(ActivityPalette.onFill)
                .frame(width: size, height: size)
                .background(Circle().fill(ActivityPalette.newFeed))
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
