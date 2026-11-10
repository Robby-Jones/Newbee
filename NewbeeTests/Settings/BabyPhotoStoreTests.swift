import Foundation
import NewbeeKit
import SwiftData
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

    @Test func savesScaledDownIntoTheBabyAndReloads() throws {
        let container = try PersistenceController.makeContainer(.inMemory)
        let store = BabyPhotoStore(container: container)
        #expect(store.image == nil)

        try store.save(makeImageData(width: 2_000, height: 1_000))
        let saved = try #require(store.image)
        #expect(max(saved.size.width * saved.scale, saved.size.height * saved.scale) <= BabyPhotoStore.maxPixelSize)
        // Saving a photo before anything else creates the baby profile that holds it.
        let baby = try #require(Baby.primary(in: container.mainContext))
        #expect(baby.photoData != nil)

        // A new store (next launch) finds the same photo.
        #expect(BabyPhotoStore(container: container).image != nil)

        store.remove()
        #expect(store.image == nil)
        #expect(baby.photoData == nil)
        #expect(BabyPhotoStore(container: container).image == nil)
    }

    /// A photo that arrives from another device shows after `reload()`.
    @Test func reloadPicksUpAPhotoFromAnotherDevice() throws {
        let container = try PersistenceController.makeContainer(.inMemory)
        let store = BabyPhotoStore(container: container)
        let baby = Baby(name: "Ella")
        container.mainContext.insert(baby)
        baby.photoData = UIImage(data: makeImageData(width: 50, height: 50))?.jpegData(compressionQuality: 0.8)
        try container.mainContext.save()
        #expect(store.image == nil)

        store.reload()
        #expect(store.image != nil)
    }

    /// Builds before schema V3 kept the photo in a file. The first launch after the update moves
    /// it into the baby profile, so it syncs, and removes the file.
    @Test func movesTheOldPhotoFileIntoTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BabyPhotoTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("BabyPhoto", isDirectory: true).appendingPathComponent("photo.jpg")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let jpeg = try #require(UIImage(data: makeImageData(width: 80, height: 80))?.jpegData(compressionQuality: 0.8))
        try jpeg.write(to: file)

        let container = try PersistenceController.makeContainer(.inMemory)
        let existing = Baby(name: "Ella")
        container.mainContext.insert(existing)
        try container.mainContext.save()

        let store = BabyPhotoStore(container: container, legacyDirectory: directory)
        #expect(store.image != nil)
        #expect(existing.photoData == jpeg)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Baby>()) == 1)
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
