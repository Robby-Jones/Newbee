import Foundation
import NewbeeKit
import Testing
import UIKit
@testable import Newbee

@MainActor
@Suite("Baby photo")
struct BabyPhotoStoreTests {
    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.pngData()!
    }

    @Test func savesScaledDownAndReloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BabyPhotoTest-\(UUID().uuidString)")
        let store = BabyPhotoStore(directory: directory)
        #expect(store.image == nil)

        try store.save(makeImageData(width: 2_000, height: 1_000))
        let saved = try #require(store.image)
        #expect(max(saved.size.width * saved.scale, saved.size.height * saved.scale) <= BabyPhotoStore.maxPixelSize)

        // A new store (next launch) finds the same photo.
        #expect(BabyPhotoStore(directory: directory).image != nil)

        store.remove()
        #expect(store.image == nil)
        #expect(BabyPhotoStore(directory: directory).image == nil)
    }

    @Test func rejectsDataThatIsNotAnImage() {
        let store = BabyPhotoStore.temporary()
        #expect(throws: BabyPhotoStore.PhotoError.self) { try store.save(Data("not a photo".utf8)) }
        #expect(store.image == nil)
    }

    @Test func deleteAllRemovesThePhoto() async throws {
        let dependencies = AppDependencies(
            clock: TestClock(), storage: .inMemory, notifications: FakeNotificationClient(),
            defaults: UserDefaults(suiteName: "BabyPhotoTests-\(UUID().uuidString)")
        )
        try dependencies.babyPhoto.save(makeImageData(width: 100, height: 100))
        try await dependencies.deleteAllData()
        #expect(dependencies.babyPhoto.image == nil)
    }
}
