import Foundation
import SwiftUI
import Testing
import XCTest
@testable import Newbee

/// The since-last-feed clock uses iOS 18's live-updating `SystemFormatStyle`, whose output isn't
/// fully documented, so the strings the Live Activity draws are pinned here on the simulator.
@Suite("Since-last-feed clock")
struct SinceLastFeedFormatTests {
    let ended = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        ended.addingTimeInterval(TimeInterval(hours * 3600 + minutes * 60 + seconds))
    }

    @Test func switchesToHoursAtTheHourMarkOrWhenTheSystemMarksItStale() {
        #expect(!SinceLastFeedFormat.showsHours(since: ended, isStale: false, now: at(0, 59, 59)))
        #expect(SinceLastFeedFormat.showsHours(since: ended, isStale: false, now: at(1, 0)))
        #expect(SinceLastFeedFormat.showsHours(since: ended, isStale: true, now: at(0, 10)))
    }
}

/// XCTest rather than Swift Testing so a failure's strings show in CI's log.
final class SinceLastFeedClockStringTests: XCTestCase {
    let ended = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        ended.addingTimeInterval(TimeInterval(hours * 3600 + minutes * 60 + seconds))
    }

    /// The whole drawn clock keeps a two-character seconds field at the end, so clipping the
    /// last three characters (":ss") always leaves hh:mm.
    func testDrawnClockEndsInSeconds() {
        let cases: [(Int, Int, Int, String)] = [
            (0, 0, 0, "00:00:00"),
            (0, 5, 12, "00:05:12"),
            (0, 59, 59, "00:59:59"),
            (1, 0, 0, "01:00:00"),
            (1, 23, 45, "01:23:45"),
            (12, 5, 0, "12:05:00"),
        ]
        for (h, m, s, expected) in cases {
            XCTAssertEqual(SinceLastFeedFormat.fullText(since: ended, at: at(h, m, s)), expected, "at \(h)h\(m)m\(s)s")
        }
    }

    func testShowsHoursAndMinutes() {
        let cases: [(Int, Int, Int, String)] = [
            (0, 0, 59, "00:00"),
            (0, 5, 0, "00:05"),
            (0, 45, 30, "00:45"),
            (0, 59, 59, "00:59"),
            (1, 0, 0, "01:00"),
            (1, 23, 45, "01:23"),
            (12, 5, 0, "12:05"),
        ]
        for (h, m, s, expected) in cases {
            let visible = SinceLastFeedFormat.visibleText(since: ended, at: at(h, m, s))
            XCTAssertEqual(visible, expected, "at \(h)h\(m)m\(s)s")
            XCTAssertEqual(visible.count, SinceLastFeedFormat.visibleTemplate.count)
        }
    }
}
