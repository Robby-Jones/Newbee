import SwiftUI
import XCTest
@testable import Newbee

/// Draws the since-last-feed timer (the view the Live Activity uses) and checks that digits
/// appear. The Lock Screen itself can't be checked here: an earlier version passed a test like
/// this and still drew shifted on a device, so docs/TESTING.md D5 stays a device check.
@MainActor
final class SinceLastFeedRenderTests: XCTestCase {
    /// Dark pixels drawn by `view` in black on white, and the width they span.
    private func ink(_ view: some View) throws -> (pixels: Int, width: Int) {
        let renderer = ImageRenderer(
            content: view
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.leading)
                .frame(width: 260, alignment: .leading)
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
        var pixels = 0, minX = width, maxX = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3 < 128 {
                    pixels += 1
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
        }
        return (pixels, maxX >= minX ? maxX - minX + 1 : 0)
    }

    private func checkTimer(sinceMinutes minutes: Double, looksLike sample: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let reference = try ink(Text(verbatim: sample).monospacedDigit())
        let timer = try ink(SinceLastFeedText(since: Date().addingTimeInterval(-minutes * 60)))
        let message = "\(minutes) min: timer \(timer.pixels) px over \(timer.width) pt, \"\(sample)\" \(reference.pixels) px over \(reference.width) pt"
        XCTAssertGreaterThan(timer.pixels, reference.pixels / 2, message, file: file, line: line)
        XCTAssertEqual(Double(timer.width), Double(reference.width), accuracy: Double(reference.width) * 0.2, message, file: file, line: line)
    }

    func testTheTimerDrawsMinutesAndSecondsInTheFirstHour() throws {
        try checkTimer(sinceMinutes: 5, looksLike: "5:00")
    }

    func testTheTimerDrawsHoursAfterAnHour() throws {
        try checkTimer(sinceMinutes: 135, looksLike: "2:15:00")
    }
}
