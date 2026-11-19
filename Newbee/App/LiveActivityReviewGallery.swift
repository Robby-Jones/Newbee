#if DEBUG
import NewbeeKit
import NewbeeShared
import SwiftUI
import UIKit

/// The since-last-feed Live Activity drawn inside the app, for review screenshots
/// (`NewbeeUITests/ReviewScreenshots.swift`): the simulator can't put a real activity on a Lock
/// Screen that a UI test can photograph. Uses the very view the widget draws
/// (`SinceLastFeedActivityContent`), on mock Lock Screen and Dynamic Island shapes.
///
/// UI tests only: `-uiTesting -liveActivityReview lockScreen` (or `lockScreenPink`, the pink
/// theme's blush card, `lockScreenThemes`, one card in each other color theme, or `island`).
struct LiveActivityReviewGallery: View {
    enum Page: String { case lockScreen, lockScreenPink, lockScreenThemes, island }

    static var requestedPage: Page? {
        guard AppConfiguration.isUITesting,
              let value = UserDefaults.standard.string(forKey: "liveActivityReview") else { return nil }
        return Page(rawValue: value)
    }

    let page: Page

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.78, blue: 0.95), Color(red: 0.95, green: 0.80, blue: 0.70)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            switch page {
            case .lockScreen: lockScreen(.night)
            case .lockScreenPink: lockScreen(.blush)
            case .lockScreenThemes: themedLockScreens
            case .island: island
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// The first two samples on each tinted theme's card.
    private var themedLockScreens: some View {
        VStack(spacing: 8) {
            ForEach([NBTheme.sage, .ocean, .lavender, .peach]) { theme in
                let palette = ActivityPalette.lockScreen(theme)
                VStack(alignment: .leading, spacing: 4) {
                    caption(theme.rawValue.capitalized)
                    ForEach(Sample.all.prefix(2)) { sample in
                        SinceLastFeedActivityContent(
                            state: sample.state, babyName: sample.name, since: sample.state.sinceLastFeedStart!,
                            style: .island, photo: sample.photo
                        )
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.background))
                        .environment(\.activityPalette, palette)
                        .environment(\.colorScheme, palette.colorScheme)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 50)
    }

    private func lockScreen(_ palette: ActivityPalette) -> some View {
        VStack(spacing: 10) {
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.bottom, 4)
            ForEach(Sample.all) { sample in
                VStack(alignment: .leading, spacing: 4) {
                    caption(sample.caption)
                    SinceLastFeedActivityContent(
                        state: sample.state, babyName: sample.name, since: sample.state.sinceLastFeedStart!,
                        style: .lockScreen, photo: sample.photo
                    )
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.background))
                    .environment(\.activityPalette, palette)
                    .environment(\.colorScheme, palette.colorScheme)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var island: some View {
        VStack(spacing: 14) {
            ForEach(Sample.all.prefix(2)) { sample in
                VStack(alignment: .leading, spacing: 4) {
                    caption("Dynamic Island, expanded · \(sample.caption)")
                    SinceLastFeedActivityContent(
                        state: sample.state, babyName: sample.name, since: sample.state.sinceLastFeedStart!,
                        style: .island, photo: sample.photo
                    )
                    .padding(.horizontal, 22)
                    .padding(.top, 44)
                    .padding(.bottom, 18)
                    .background(alignment: .top) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 46, style: .continuous).fill(Color.black)
                            // Where the camera sits.
                            Capsule().fill(Color(white: 0.08)).frame(width: 120, height: 34).padding(.top, 8)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.top, 6)
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(white: 0.15))
            .padding(.leading, 6)
    }
}

private struct Sample: Identifiable {
    let id: Int
    let caption: String
    let name: String
    let photo: UIImage?
    let state: FeedingActivityAttributes.ContentState

    static let all: [Sample] = [
        Sample(
            id: 0, caption: "Bottle · photo", name: "Millie", photo: samplePhoto,
            state: ended(minutesAgo: 28.5, left: 0, right: 0, side: .right, bottle: BottleAmount(1, .fluidOunces))
        ),
        Sample(
            id: 1, caption: "Breastfeed · photo · over an hour", name: "Millie", photo: samplePhoto,
            state: ended(minutesAgo: 65, left: 12 * 60, right: 9 * 60, side: .right, bottle: nil)
        ),
        Sample(
            id: 2, caption: "No photo: initial", name: "Ella", photo: nil,
            state: ended(minutesAgo: 6, left: 0, right: 0, side: .left, bottle: BottleAmount(90, .milliliters))
        ),
        Sample(
            id: 3, caption: "No name or photo · one side", name: "", photo: nil,
            state: ended(minutesAgo: 182, left: 15 * 60, right: 0, side: .left, bottle: nil)
        ),
    ]

    private static func ended(
        minutesAgo: Double, left: TimeInterval, right: TimeInterval, side: Side, bottle: BottleAmount?
    ) -> FeedingActivityAttributes.ContentState {
        let end = Date.now.addingTimeInterval(-minutesAgo * 60)
        return FeedingActivityAttributes.ContentState(
            status: .ended, currentSide: side, sessionStart: end.addingTimeInterval(-(left + right)),
            currentSegmentStart: nil, leftAccumulated: left, rightAccumulated: right,
            pausedAt: end, revision: 1, lastBottle: bottle
        )
    }

    /// A stand-in for a baby photo: a soft background with a baby emoji, made square like the
    /// avatar file the app saves.
    private static let samplePhoto: UIImage = {
        let size = CGSize(width: 192, height: 192)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(red: 1, green: 0.86, blue: 0.75, alpha: 1).cgColor, UIColor(red: 0.98, green: 0.7, blue: 0.62, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let emoji = NSAttributedString(string: "👶", attributes: [.font: UIFont.systemFont(ofSize: 130)])
            let textSize = emoji.size()
            emoji.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2 + 6))
        }
        return LiveActivityAvatar.squareThumbnail(of: image)
    }()
}
#endif
