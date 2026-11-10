import Foundation
import Observation
import SwiftData
import UIKit

/// The baby's profile photo, chosen in Settings and shown at the top of Home.
///
/// Kept as a small JPEG in `Baby.photoData` (schema V3), so it syncs through iCloud with the rest
/// of the baby's profile. Builds before V3 kept it in a file in Application Support; that file is
/// moved into the store on the first launch after the update.
@MainActor
@Observable
final class BabyPhotoStore {
    /// The longest side of the saved photo, in pixels. Plenty for a 96 pt circle at 3x.
    static let maxPixelSize: CGFloat = 600

    /// The current photo, or `nil` when none is set.
    private(set) var image: UIImage?

    @ObservationIgnored private let container: ModelContainer?
    @ObservationIgnored private let legacyFileURL: URL?
    /// The bytes `image` was decoded from, so `reload()` only decodes a changed photo.
    @ObservationIgnored private var loadedData: Data?

    /// - Parameters:
    ///   - container: The store holding the baby. `nil` when the store couldn't be opened; the
    ///     photo is then only kept in memory.
    ///   - legacyDirectory: Where builds before schema V3 saved the photo file, to move it into
    ///     the store. Only the real store passes it.
    init(container: ModelContainer?, legacyDirectory: URL? = nil) {
        self.container = container
        legacyFileURL = legacyDirectory?
            .appendingPathComponent("BabyPhoto", isDirectory: true)
            .appendingPathComponent("photo.jpg")
        moveLegacyFileIntoStore()
        reload()
    }

    /// Application Support, where builds before schema V3 kept `BabyPhoto/photo.jpg`.
    static var legacyDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// A store on its own empty in-memory container, for previews.
    static func temporary() -> BabyPhotoStore {
        BabyPhotoStore(container: try? PersistenceController.makeContainer(.inMemory))
    }

    /// Saves picked image data (any format UIKit reads), scaled down and re-encoded as JPEG.
    /// Creates the baby profile if there isn't one yet.
    func save(_ data: Data) throws {
        guard let picked = UIImage(data: data) else { throw PhotoError.unreadable }
        let scaled = Self.scaled(picked, maxPixelSize: Self.maxPixelSize)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { throw PhotoError.unreadable }
        if let context = container?.mainContext {
            do {
                Baby.primary(in: context, creatingIfMissing: true)?.photoData = jpeg
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        image = scaled
        loadedData = jpeg
    }

    /// Removes the photo. Also used by "Delete all data".
    func remove() {
        if let context = container?.mainContext, let baby = Baby.primary(in: context), baby.photoData != nil {
            baby.photoData = nil
            try? context.save()
        }
        if let legacyFileURL {
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
        image = nil
        loadedData = nil
    }

    /// Reads the photo from the store again, e.g. after iCloud brought in a change from another
    /// device or two baby profiles were merged.
    func reload() {
        guard let context = container?.mainContext else { return }
        let data = Baby.primary(in: context)?.photoData
        guard data != loadedData else { return }
        loadedData = data
        image = data.flatMap(UIImage.init(data:))
    }

    /// Moves a photo saved by a build before schema V3 into the store, unless the baby already
    /// has one (e.g. from another device). On failure the file stays for the next launch.
    private func moveLegacyFileIntoStore() {
        guard let legacyFileURL, let context = container?.mainContext,
              let data = try? Data(contentsOf: legacyFileURL) else { return }
        do {
            if let baby = Baby.primary(in: context, creatingIfMissing: true), baby.photoData == nil {
                baby.photoData = data
            }
            try context.save()
            try? FileManager.default.removeItem(at: legacyFileURL)
        } catch {
            context.rollback()
        }
    }

    enum PhotoError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            String(localized: "That photo couldn't be used. Try another one.")
        }
    }

    /// Draws the image upright at no more than `maxPixelSize` on its longest side.
    private static func scaled(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        let factor = longest > maxPixelSize ? maxPixelSize / longest : 1
        let size = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
