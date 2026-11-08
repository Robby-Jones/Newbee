import Foundation
import Observation
import UIKit

/// The baby's profile photo, chosen in Settings and shown at the top of Home.
///
/// Kept as a small JPEG file in Application Support rather than in SwiftData, so adding it
/// needs no schema change (docs/DATA_MODEL.md, "Not in SwiftData"). Only stored on this iPhone.
@MainActor
@Observable
final class BabyPhotoStore {
    /// The longest side of the saved photo, in pixels. Plenty for a 96 pt circle at 3x.
    static let maxPixelSize: CGFloat = 600

    /// The current photo, or `nil` when none is set.
    private(set) var image: UIImage?

    @ObservationIgnored private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("BabyPhoto", isDirectory: true).appendingPathComponent("photo.jpg")
        image = (try? Data(contentsOf: fileURL)).flatMap(UIImage.init(data:))
    }

    /// A fresh, empty throwaway location for in-memory stores (UI tests, previews, unit tests),
    /// so they never touch the real photo or each other's.
    static func temporary() -> BabyPhotoStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BabyPhoto-\(UUID().uuidString)", isDirectory: true)
        return BabyPhotoStore(directory: directory)
    }

    /// Saves picked image data (any format UIKit reads), scaled down and re-encoded as JPEG.
    func save(_ data: Data) throws {
        guard let picked = UIImage(data: data) else { throw PhotoError.unreadable }
        let scaled = Self.scaled(picked, maxPixelSize: Self.maxPixelSize)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { throw PhotoError.unreadable }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        image = scaled
    }

    /// Removes the photo. Also used by "Delete all data".
    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        image = nil
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
