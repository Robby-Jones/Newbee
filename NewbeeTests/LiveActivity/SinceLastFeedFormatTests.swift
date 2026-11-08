import Foundation
import SwiftUI
import Testing
import XCTest
@testable import Newbee

/// The since-last-feed clock uses iOS 18's live-updating `SystemFormatStyle`, whose exact output
/// isn't fully documented, so the strings the Live Activity draws are pinned here on the simulator.
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

/// XCTest rather than Swift Testing so CI's log shows the failure message with the real strings.
final class SinceLastFeedClockStringTests: XCTestCase {
    let ended = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        ended.addingTimeInterval(TimeInterval(hours * 3600 + minutes * 60 + seconds))
    }

    func testShowsHoursAndMinutes() {
        let cases: [(Int, Int, Int, String)] = [
            (0, 0, 0, "0:00"),
            (0, 0, 59, "0:00"),
            (0, 5, 0, "0:05"),
            (0, 45, 30, "0:45"),
            (0, 59, 59, "0:59"),
            (1, 0, 0, "1:00"),
            (1, 23, 45, "1:23"),
            (12, 5, 0, "12:05"),
        ]
        for (h, m, s, expected) in cases {
            let date = at(h, m, s)
            XCTAssertEqual(
                SinceLastFeedFormat.text(since: ended, at: date), expected,
                "at \(h)h\(m)m\(s)s: \(diagnostics(at: date))"
            )
        }
    }

    /// Raw output of the candidate styles, shown when an assertion fails.
    private func diagnostics(at date: Date) -> String {
        func render(_ style: SystemFormatStyle.Stopwatch) -> String { String(style.format(date).characters) }
        let candidates: [(String, SystemFormatStyle.Stopwatch)] = [
            ("minutes", SinceLastFeedFormat.minutes(since: ended)),
            ("hoursAndMinutes", SinceLastFeedFormat.hoursAndMinutes(since: ended)),
            ("sw h=true f=2 p=60", .init(startingAt: ended, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(60))),
            ("sw h=false f=2 p=1", .init(startingAt: ended, showsHours: false, maxFieldCount: 2, maxPrecision: .seconds(1))),
            ("sw h=true f=3 p=1", .init(startingAt: ended, showsHours: true, maxFieldCount: 3, maxPrecision: .seconds(1))),
        ]
        let timer = SystemFormatStyle.Timer(
            countingUpIn: ended..<ended.addingTimeInterval(24 * 3600), showsHours: false, maxFieldCount: 1
        )
        return candidates.map { "\($0.0)=\"\(render($0.1))\"" }.joined(separator: " ")
            + " timer h=false f=1=\"\(String(timer.format(date).characters))\""
    }
}
