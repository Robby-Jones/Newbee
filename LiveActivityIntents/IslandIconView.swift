import NewbeeKit
import NewbeeShared
import SwiftUI
import UIKit

/// The icon beside the count in the minimized Dynamic Island once a feed has ended, per Settings'
/// island icon (`ContentState.islandIcon`, `nil` = the bee). Also drawn in Settings' picker.
struct IslandIconView: View {
    let icon: IslandIcon
    /// The last feed, for `lastFeed`.
    let state: FeedingActivityAttributes.ContentState
    /// The icon's width in points (the bee is a little shorter than wide).
    var size: CGFloat = 24
    /// The minimal island: a smaller circle beside another app's activity.
    var minimal = false

    var body: some View {
        switch icon {
        case .bee:
            TinyBee(width: size)
        case .babyPhoto:
            // The same ≤84 px / 4 KB copy as the expanded island's avatar: larger images made iOS
            // drop the whole activity (2026-11-19). No photo saved: the bee.
            if let photo = LiveActivityAvatar.load() {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                TinyBee(width: size)
            }
        case .lastFeed:
            let color = Self.lastFeedColor(state)
            if minimal {
                ZStack {
                    Circle().strokeBorder(color, lineWidth: 2)
                    FeedIcon(Self.lastFeedGlyph(state), fixedSize: size * 0.6)
                        .foregroundStyle(color)
                }
                .frame(width: size, height: size)
            } else {
                FeedIcon(Self.lastFeedGlyph(state), fixedSize: size * 0.85)
                    .foregroundStyle(color)
            }
        case .clock:
            if minimal {
                ZStack {
                    Circle().strokeBorder(Color(white: 0.7), lineWidth: 2)
                    Image(systemName: "clock")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(Color(white: 0.7))
                }
                .frame(width: size, height: size)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: size * 0.6, weight: .bold))
                    .foregroundStyle(Color(white: 0.7))
            }
        }
    }

    /// The breastfeed icon, or the bottle while counting from a bottle.
    static func lastFeedGlyph(_ state: FeedingActivityAttributes.ContentState) -> FeedGlyph {
        state.lastBottle == nil ? .breastfeed : .bottle
    }

    /// The side the breastfeed ended on, or bottle peach, like the Lock Screen's `LastFeedDetail`.
    static func lastFeedColor(_ state: FeedingActivityAttributes.ContentState) -> Color {
        state.lastBottle == nil ? NBColor.side(state.currentSide) : NBColor.bottleBreastMilk
    }
}

extension IslandIcon {
    var title: String {
        switch self {
        case .bee: String(localized: "Bee")
        case .babyPhoto: String(localized: "Baby photo")
        case .lastFeed: String(localized: "Last feed")
        case .clock: String(localized: "Clock")
        }
    }
}
