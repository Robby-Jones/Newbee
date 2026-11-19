// Compiled into both the app (which writes the file) and the widget extension (which reads it).

import Foundation
import UIKit

/// The baby's photo for the Live Activity: a small square JPEG in the App Group container, next
/// to the store. The widget extension can't open the store's photo itself, and an activity's
/// content is limited to 4 KB, so the app keeps this copy in step with the profile photo
/// (`BabyPhotoStore`) and the activity reads it each time it's drawn.
///
/// Keep it tiny. iOS won't show a Live Activity at all when an image in it is too large (the
/// widget's archive fails, worst in the Dynamic Island): a 192 px copy (2026-11-19) left Settings'
/// Refresh with a checkmark and nothing on the Lock Screen. Developers report 320 px failing and
/// 84 px working, so this stays at 84 px and a few KB, a little soft in the 60 pt circle.
enum LiveActivityAvatar {
    /// Pixels on each side.
    static let pixelSize: CGFloat = 84
    /// The most bytes the JPEG may take; quality steps down until it fits.
    static let maxBytes = 4_000

    /// `<App Group>/Library/Caches/LiveActivity/avatar.jpg`, or `nil` without an App Group (a
    /// build without the entitlement).
    static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "NewbeeAppGroup") as? String, !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container
            .appending(path: "Library/Caches/LiveActivity", directoryHint: .isDirectory)
            .appending(path: "avatar.jpg")
    }

    /// Writes `image` cropped to a centered square at `pixelSize`, or removes the file for `nil`.
    static func save(_ image: UIImage?, to url: URL) {
        guard let image else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = jpeg(squareThumbnail(of: image)) else {
            // Never leave an older copy that might be too large to draw.
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // The activity falls back to the initial.
        }
    }

    /// The saved photo, or `nil` when none is saved. A file too large to draw safely (e.g. from
    /// an earlier build) is ignored, so the activity shows the initial instead of not showing.
    static func load(from url: URL? = fileURL) -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url), data.count <= maxBytes,
              let image = UIImage(data: data),
              image.size.width * image.scale <= pixelSize, image.size.height * image.scale <= pixelSize
        else { return nil }
        return image
    }

    /// JPEG data at the highest quality that fits in `maxBytes`, or `nil` if none does.
    static func jpeg(_ image: UIImage) -> Data? {
        for quality in stride(from: 0.8, through: 0.2, by: -0.1) {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        return nil
    }

    /// `image` filling a `pixelSize` square, centered (like `scaledToFill` in a circle).
    static func squareThumbnail(of image: UIImage) -> UIImage {
        let side = pixelSize
        let scale = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
    }
}
