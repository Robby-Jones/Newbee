import SwiftUI
import XCTest
@testable import Newbee

/// Draws the since-last-feed clock (the view the Live Activity uses) and checks that digits
/// actually appear, about as wide as "00:00": not blank, and no seconds past the clip. A device
/// run once showed the Live Activity with no number at all.
@MainActor
final class SinceLastFeedRenderTests: XCTestCase {
    private struct Ink {
        var pixels = 0
        var width = 0
    }

    /// Dark pixels drawn by `view` in black on white, and the width they span.
    private func ink(_ view: some View) throws -> Ink {
        let renderer = ImageRenderer(
            content: view
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black)
                .padding(8)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "nothing rendered")
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var result = Ink()
        var minX = width, maxX = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let luminance = (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
                if luminance < 128 {
                    result.pixels += 1
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
        }
        result.width = maxX >= minX ? maxX - minX + 1 : 0
        return result
    }

    private func checkClock(sinceMinutes minutes: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        let template = try ink(Text(verbatim: "00:00").monospacedDigit())
        let clock = try ink(SinceLastFeedText(lastFeedEnded: Date().addingTimeInterval(-minutes * 60), isStale: false))
        let message = "\(minutes) min: clock ink \(clock.pixels) px over \(clock.width) pt, template \(template.pixels) px over \(template.width) pt"
        XCTAssertGreaterThan(clock.pixels, template.pixels / 2, message, file: file, line: line)
        XCTAssertGreaterThan(Double(clock.width), Double(template.width) * 0.8, message, file: file, line: line)
        XCTAssertLessThan(Double(clock.width), Double(template.width) * 1.15, message, file: file, line: line)
    }

    func testTheClockDrawsDigitsInTheFirstHour() throws {
        try checkClock(sinceMinutes: 5)
    }

    func testTheClockDrawsDigitsAfterAnHour() throws {
        try checkClock(sinceMinutes: 135)
    }
}
