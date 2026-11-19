#if canImport(SwiftUI)
import SwiftUI

/// The three feed types, each with Newbee's own icon.
public enum FeedGlyph: String, CaseIterable, Sendable {
    case breastfeed, bottle, pumping
}

/// Newbee's duotone feed type icon: solid main shapes plus a lighter second tone
/// (the baby, the empty part of a bottle). Both tones use the current foreground
/// style, so callers color it with `.foregroundStyle` like an SF Symbol.
///
/// Drawn on a 24 × 24 grid (sources: project-files feed-icons/svg).
public struct FeedIcon: View {
    /// How strong the second tone is, against the main shapes.
    public static let secondaryOpacity = 0.45

    let glyph: FeedGlyph
    let scales: Bool
    let baseSize: CGFloat
    @ScaledMetric private var scaledSize: CGFloat

    /// An icon `size` points square that grows with Dynamic Type like `style`.
    public init(_ glyph: FeedGlyph, size: CGFloat = 20, relativeTo style: Font.TextStyle = .body) {
        self.glyph = glyph
        self.scales = true
        self.baseSize = size
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    /// An icon that stays `fixedSize` points square (Live Activity, PDF report).
    public init(_ glyph: FeedGlyph, fixedSize: CGFloat) {
        self.glyph = glyph
        self.scales = false
        self.baseSize = fixedSize
        _scaledSize = ScaledMetric(wrappedValue: fixedSize)
    }

    public var body: some View {
        let side = scales ? scaledSize : baseSize
        ZStack {
            FeedGlyphShape(glyph: glyph, tone: .secondary)
                .opacity(Self.secondaryOpacity)
            FeedGlyphShape(glyph: glyph, tone: .primary)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// One tone of a feed icon, scaled from the 24-point grid to fit its frame.
public struct FeedGlyphShape: Shape {
    public enum Tone: Sendable { case primary, secondary }

    public let glyph: FeedGlyph
    public let tone: Tone

    public init(glyph: FeedGlyph, tone: Tone) {
        self.glyph = glyph
        self.tone = tone
    }

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let base: Path = switch (glyph, tone) {
        case (.breastfeed, .primary): FeedGlyphPaths.breastfeedPrimary()
        case (.breastfeed, .secondary): FeedGlyphPaths.breastfeedSecondary()
        case (.bottle, .primary): FeedGlyphPaths.bottlePrimary()
        case (.bottle, .secondary): FeedGlyphPaths.bottleSecondary()
        case (.pumping, .primary): FeedGlyphPaths.pumpingPrimary()
        case (.pumping, .secondary): FeedGlyphPaths.pumpingSecondary()
        }
        return base.applying(
            CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
                .scaledBy(x: scale, y: scale)
        )
    }
}

#if canImport(UIKit)
import UIKit

public extension Image {
    /// A feed icon as a template image, for places that only take an `Image`, like menu items.
    /// Keeps both tones (the second one as lower alpha), tinted like any template image.
    @MainActor
    init(feedGlyph: FeedGlyph, pointSize: CGFloat = 20) {
        self = Image(uiImage: FeedIconImageCache.image(feedGlyph, pointSize: pointSize)).renderingMode(.template)
    }
}

@MainActor
private enum FeedIconImageCache {
    static var images: [String: UIImage] = [:]

    static func image(_ glyph: FeedGlyph, pointSize: CGFloat) -> UIImage {
        let key = "\(glyph.rawValue)-\(pointSize)"
        if let cached = images[key] { return cached }
        let renderer = ImageRenderer(content: FeedIcon(glyph, fixedSize: pointSize).foregroundStyle(.black))
        renderer.scale = 3
        let image = (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysTemplate)
        images[key] = image
        return image
    }
}
#endif

/// The icon outlines on a 24 × 24 grid, generated from the SVG sources.
enum FeedGlyphPaths {
    /// breastfeed, primary tone.
    static func breastfeedPrimary() -> Path {
        var path = Path()
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 5.4, y: 5.2))
            p.addCurve(to: CGPoint(x: 8.2, y: 8), control1: CGPoint(x: 5.4, y: 6.746), control2: CGPoint(x: 6.654, y: 8))
            p.addCurve(to: CGPoint(x: 11, y: 5.2), control1: CGPoint(x: 9.746, y: 8), control2: CGPoint(x: 11, y: 6.746))
            p.addCurve(to: CGPoint(x: 8.2, y: 2.4), control1: CGPoint(x: 11, y: 3.654), control2: CGPoint(x: 9.746, y: 2.4))
            p.addCurve(to: CGPoint(x: 5.4, y: 5.2), control1: CGPoint(x: 6.654, y: 2.4), control2: CGPoint(x: 5.4, y: 3.654))
            p.closeSubpath()
        })
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 3.4, y: 21.6))
            p.addLine(to: CGPoint(x: 3.4, y: 14.8))
            p.addCurve(to: CGPoint(x: 8.8, y: 9.4), control1: CGPoint(x: 3.4, y: 11.818), control2: CGPoint(x: 5.818, y: 9.4))
            p.addLine(to: CGPoint(x: 9.2, y: 9.4))
            p.addCurve(to: CGPoint(x: 10.807, y: 10.22), control1: CGPoint(x: 9.835, y: 9.403), control2: CGPoint(x: 10.432, y: 9.707))
            p.addCurve(to: CGPoint(x: 11.1, y: 12), control1: CGPoint(x: 11.182, y: 10.733), control2: CGPoint(x: 11.291, y: 11.394))
            p.addLine(to: CGPoint(x: 9.6, y: 16))
            p.addLine(to: CGPoint(x: 9.6, y: 21.6))
            p.closeSubpath()
        })
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 5.2, y: 16.6))
            p.addCurve(to: CGPoint(x: 19.8, y: 14.8), control1: CGPoint(x: 9, y: 20), control2: CGPoint(x: 16, y: 19.8))
        }.strokedPath(StrokeStyle(lineWidth: 2.6, lineCap: .round)))
        return path
    }

    /// breastfeed, secondary tone.
    static func breastfeedSecondary() -> Path {
        var path = Path()
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 12.6, y: 11.6))
            p.addCurve(to: CGPoint(x: 15.4, y: 14.4), control1: CGPoint(x: 12.6, y: 13.146), control2: CGPoint(x: 13.854, y: 14.4))
            p.addCurve(to: CGPoint(x: 18.2, y: 11.6), control1: CGPoint(x: 16.946, y: 14.4), control2: CGPoint(x: 18.2, y: 13.146))
            p.addCurve(to: CGPoint(x: 15.4, y: 8.8), control1: CGPoint(x: 18.2, y: 10.054), control2: CGPoint(x: 16.946, y: 8.8))
            p.addCurve(to: CGPoint(x: 12.6, y: 11.6), control1: CGPoint(x: 13.854, y: 8.8), control2: CGPoint(x: 12.6, y: 10.054))
            p.closeSubpath()
        })
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 9.6, y: 15.4))
            p.addCurve(to: CGPoint(x: 15.6, y: 14.8), control1: CGPoint(x: 11.4, y: 14.2), control2: CGPoint(x: 14, y: 14))
            p.addLine(to: CGPoint(x: 15, y: 17.6))
            p.addLine(to: CGPoint(x: 10, y: 17.8))
            p.closeSubpath()
        })
        return path
    }

    /// bottle, primary tone.
    static func bottlePrimary() -> Path {
        var path = Path()
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 9.2, y: 5.2))
            p.addLine(to: CGPoint(x: 14.8, y: 5.2))
            p.addCurve(to: CGPoint(x: 16, y: 6.4), control1: CGPoint(x: 15.463, y: 5.2), control2: CGPoint(x: 16, y: 5.737))
            p.addLine(to: CGPoint(x: 16, y: 7.2))
            p.addCurve(to: CGPoint(x: 14.8, y: 8.4), control1: CGPoint(x: 16, y: 7.863), control2: CGPoint(x: 15.463, y: 8.4))
            p.addLine(to: CGPoint(x: 9.2, y: 8.4))
            p.addCurve(to: CGPoint(x: 8.351, y: 8.049), control1: CGPoint(x: 8.882, y: 8.4), control2: CGPoint(x: 8.577, y: 8.274))
            p.addCurve(to: CGPoint(x: 8, y: 7.2), control1: CGPoint(x: 8.126, y: 7.823), control2: CGPoint(x: 8, y: 7.518))
            p.addLine(to: CGPoint(x: 8, y: 6.4))
            p.addCurve(to: CGPoint(x: 8.351, y: 5.551), control1: CGPoint(x: 8, y: 6.082), control2: CGPoint(x: 8.126, y: 5.777))
            p.addCurve(to: CGPoint(x: 9.2, y: 5.2), control1: CGPoint(x: 8.577, y: 5.326), control2: CGPoint(x: 8.882, y: 5.2))
            p.closeSubpath()
        })
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 8.4, y: 12.6))
            p.addLine(to: CGPoint(x: 15.6, y: 12.6))
            p.addLine(to: CGPoint(x: 15.6, y: 19.2))
            p.addCurve(to: CGPoint(x: 12.6, y: 22.2), control1: CGPoint(x: 15.6, y: 20.857), control2: CGPoint(x: 14.257, y: 22.2))
            p.addLine(to: CGPoint(x: 11.4, y: 22.2))
            p.addCurve(to: CGPoint(x: 8.4, y: 19.2), control1: CGPoint(x: 9.743, y: 22.2), control2: CGPoint(x: 8.4, y: 20.857))
            p.closeSubpath()
            p.move(to: CGPoint(x: 11.6, y: 14.35))
            p.addCurve(to: CGPoint(x: 11.14, y: 14.54), control1: CGPoint(x: 11.428, y: 14.35), control2: CGPoint(x: 11.262, y: 14.418))
            p.addCurve(to: CGPoint(x: 10.95, y: 15), control1: CGPoint(x: 11.018, y: 14.662), control2: CGPoint(x: 10.95, y: 14.828))
            p.addLine(to: CGPoint(x: 10.95, y: 15))
            p.addCurve(to: CGPoint(x: 11.14, y: 15.46), control1: CGPoint(x: 10.95, y: 15.172), control2: CGPoint(x: 11.018, y: 15.338))
            p.addCurve(to: CGPoint(x: 11.6, y: 15.65), control1: CGPoint(x: 11.262, y: 15.582), control2: CGPoint(x: 11.428, y: 15.65))
            p.addLine(to: CGPoint(x: 13.6, y: 15.65))
            p.addCurve(to: CGPoint(x: 14.06, y: 15.46), control1: CGPoint(x: 13.772, y: 15.65), control2: CGPoint(x: 13.938, y: 15.582))
            p.addCurve(to: CGPoint(x: 14.25, y: 15), control1: CGPoint(x: 14.182, y: 15.338), control2: CGPoint(x: 14.25, y: 15.172))
            p.addLine(to: CGPoint(x: 14.25, y: 15))
            p.addCurve(to: CGPoint(x: 14.06, y: 14.54), control1: CGPoint(x: 14.25, y: 14.828), control2: CGPoint(x: 14.182, y: 14.662))
            p.addCurve(to: CGPoint(x: 13.6, y: 14.35), control1: CGPoint(x: 13.938, y: 14.418), control2: CGPoint(x: 13.772, y: 14.35))
            p.closeSubpath()
            p.move(to: CGPoint(x: 11.6, y: 16.95))
            p.addCurve(to: CGPoint(x: 10.95, y: 17.6), control1: CGPoint(x: 11.241, y: 16.95), control2: CGPoint(x: 10.95, y: 17.241))
            p.addLine(to: CGPoint(x: 10.95, y: 17.6))
            p.addCurve(to: CGPoint(x: 11.6, y: 18.25), control1: CGPoint(x: 10.95, y: 17.959), control2: CGPoint(x: 11.241, y: 18.25))
            p.addLine(to: CGPoint(x: 13.6, y: 18.25))
            p.addCurve(to: CGPoint(x: 14.25, y: 17.6), control1: CGPoint(x: 13.959, y: 18.25), control2: CGPoint(x: 14.25, y: 17.959))
            p.addLine(to: CGPoint(x: 14.25, y: 17.6))
            p.addCurve(to: CGPoint(x: 13.6, y: 16.95), control1: CGPoint(x: 14.25, y: 17.241), control2: CGPoint(x: 13.959, y: 16.95))
            p.closeSubpath()
        })
        return path
    }

    /// bottle, secondary tone.
    static func bottleSecondary() -> Path {
        var path = Path()
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 10.4, y: 5.6))
            p.addLine(to: CGPoint(x: 10.4, y: 4.4))
            p.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 10.4, y: 3), control2: CGPoint(x: 11.1, y: 2))
            p.addCurve(to: CGPoint(x: 13.6, y: 4.4), control1: CGPoint(x: 12.9, y: 2), control2: CGPoint(x: 13.6, y: 3))
            p.addLine(to: CGPoint(x: 13.6, y: 5.6))
            p.closeSubpath()
        })
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 8.4, y: 8.4))
            p.addLine(to: CGPoint(x: 15.6, y: 8.4))
            p.addLine(to: CGPoint(x: 15.6, y: 19.2))
            p.addCurve(to: CGPoint(x: 12.6, y: 22.2), control1: CGPoint(x: 15.6, y: 20.857), control2: CGPoint(x: 14.257, y: 22.2))
            p.addLine(to: CGPoint(x: 11.4, y: 22.2))
            p.addCurve(to: CGPoint(x: 8.4, y: 19.2), control1: CGPoint(x: 9.743, y: 22.2), control2: CGPoint(x: 8.4, y: 20.857))
            p.closeSubpath()
        })
        return path
    }

    /// pumping, primary tone.
    static func pumpingPrimary() -> Path {
        var path = Path()
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 10.2, y: 7.8))
            p.addCurve(to: CGPoint(x: 3, y: 3.6), control1: CGPoint(x: 7, y: 7.6), control2: CGPoint(x: 4.4, y: 6))
            p.addCurve(to: CGPoint(x: 3, y: 16.2), control1: CGPoint(x: 1.4, y: 7.6), control2: CGPoint(x: 1.4, y: 12.2))
            p.addCurve(to: CGPoint(x: 10.2, y: 12), control1: CGPoint(x: 4.4, y: 13.8), control2: CGPoint(x: 7, y: 12.2))
            p.closeSubpath()
        })
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 10.8, y: 7.2))
            p.addLine(to: CGPoint(x: 17.6, y: 7.2))
            p.addCurve(to: CGPoint(x: 18.8, y: 8.4), control1: CGPoint(x: 18.263, y: 7.2), control2: CGPoint(x: 18.8, y: 7.737))
            p.addLine(to: CGPoint(x: 18.8, y: 9.4))
            p.addCurve(to: CGPoint(x: 17.6, y: 10.6), control1: CGPoint(x: 18.8, y: 10.063), control2: CGPoint(x: 18.263, y: 10.6))
            p.addLine(to: CGPoint(x: 10.8, y: 10.6))
            p.addCurve(to: CGPoint(x: 9.6, y: 9.4), control1: CGPoint(x: 10.137, y: 10.6), control2: CGPoint(x: 9.6, y: 10.063))
            p.addLine(to: CGPoint(x: 9.6, y: 8.4))
            p.addCurve(to: CGPoint(x: 10.8, y: 7.2), control1: CGPoint(x: 9.6, y: 7.737), control2: CGPoint(x: 10.137, y: 7.2))
            p.closeSubpath()
        })
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 10.2, y: 15.4))
            p.addLine(to: CGPoint(x: 18.2, y: 15.4))
            p.addLine(to: CGPoint(x: 18.2, y: 19.2))
            p.addCurve(to: CGPoint(x: 17.38, y: 21.18), control1: CGPoint(x: 18.2, y: 19.943), control2: CGPoint(x: 17.905, y: 20.655))
            p.addCurve(to: CGPoint(x: 15.4, y: 22), control1: CGPoint(x: 16.855, y: 21.705), control2: CGPoint(x: 16.143, y: 22))
            p.addLine(to: CGPoint(x: 13, y: 22))
            p.addCurve(to: CGPoint(x: 10.2, y: 19.2), control1: CGPoint(x: 11.454, y: 22), control2: CGPoint(x: 10.2, y: 20.746))
            p.closeSubpath()
        })
        return path
    }

    /// pumping, secondary tone.
    static func pumpingSecondary() -> Path {
        var path = Path()
        path.addPath(Path { p in
            p.move(to: CGPoint(x: 10.2, y: 10.6))
            p.addLine(to: CGPoint(x: 18.2, y: 10.6))
            p.addLine(to: CGPoint(x: 18.2, y: 19.2))
            p.addCurve(to: CGPoint(x: 17.38, y: 21.18), control1: CGPoint(x: 18.2, y: 19.943), control2: CGPoint(x: 17.905, y: 20.655))
            p.addCurve(to: CGPoint(x: 15.4, y: 22), control1: CGPoint(x: 16.855, y: 21.705), control2: CGPoint(x: 16.143, y: 22))
            p.addLine(to: CGPoint(x: 13, y: 22))
            p.addCurve(to: CGPoint(x: 10.2, y: 19.2), control1: CGPoint(x: 11.454, y: 22), control2: CGPoint(x: 10.2, y: 20.746))
            p.closeSubpath()
        })
        return path
    }
}

#endif
