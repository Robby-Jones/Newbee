import Foundation
import NewbeeKit
import NewbeeShared
import Testing
import UIKit
@testable import Newbee

/// The since-last-feed Live Activity's feed line and the photo copy it reads.
@MainActor
struct SinceLastFeedActivityTests {
    private func ended(left: TimeInterval, right: TimeInterval, bottle: BottleAmount? = nil) -> FeedingActivityAttributes.ContentState {
        FeedingActivityAttributes.ContentState(
            status: .ended, currentSide: .right, sessionStart: .now.addingTimeInterval(-3600),
            currentSegmentStart: nil, leftAccumulated: left, rightAccumulated: right,
            pausedAt: .now, revision: 1, lastBottle: bottle
        )
    }

    @Test func breastfeedShowsEachUsedSide() {
        #expect(LastFeedDetail.amount(ended(left: 12 * 60, right: 9 * 60)) == "L 12m · R 9m")
        #expect(LastFeedDetail.amount(ended(left: 15 * 60, right: 0)) == "L 15m")
        #expect(LastFeedDetail.amount(ended(left: 0, right: 0)) == "0m")
    }

    @Test func bottleShowsItsAmount() {
        #expect(LastFeedDetail.amount(ended(left: 0, right: 0, bottle: BottleAmount(90, .milliliters))) == "90 mL")
    }

    @Test func avatarIsSavedSquareAndRemoved() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "avatar.jpg")
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        LiveActivityAvatar.save(wide, to: url)
        let saved = try #require(LiveActivityAvatar.load(from: url))
        #expect(saved.size.width * saved.scale == LiveActivityAvatar.pixelSize)
        #expect(saved.size.height * saved.scale == LiveActivityAvatar.pixelSize)

        LiveActivityAvatar.save(nil, to: url)
        #expect(LiveActivityAvatar.load(from: url) == nil)
    }

    @Test func photoStoreKeepsTheLiveActivityCopyInStep() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "avatar.jpg")
        let container = try PersistenceController.makeContainer(.inMemory)
        let store = BabyPhotoStore(container: container, liveActivityAvatarURL: url)
        #expect(LiveActivityAvatar.load(from: url) == nil)

        let photo = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
        try store.save(try #require(photo.pngData()))
        #expect(LiveActivityAvatar.load(from: url) != nil)

        store.remove()
        #expect(LiveActivityAvatar.load(from: url) == nil)
    }
}
