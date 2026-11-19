// Compiled into both the app (which writes the file) and the widget extension (which reads it).

import Foundation
import UIKit

/// The baby's photo for the Live Activity: a small square JPEG in the App Group container, next
/// to the store. The widget extension can't open the store's photo itself, and an activity's
/// content is limited to 4 KB, so the app keeps this copy in step with the profile photo
/// (`BabyPhotoStore`) and the activity reads it each time it's drawn.
enum LiveActivityAvatar {
    /// Pixels on each side: a 64 pt circle at 3x, small enough for the Lock Screen to draw.
    static let pixelSize: CGFloat = 192

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
        guard let data = squareThumbnail(of: image).jpegData(compressionQuality: 0.8) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // The activity falls back to the initial.
        }
    }

    /// The saved photo, or `nil` when none is saved.
    static func load(from url: URL? = fileURL) -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
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
