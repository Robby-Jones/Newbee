// Compiled into both the app and the widget extension (like the intents in this folder), so the
// app's tests check the exact formats the Live Activity renders.

import Foundation
import SwiftUI

/// The since-last-feed count on the Live Activity, as a ticking `hh:mm` clock: "00:05", "00:45",
/// "01:23", "12:05".
///
/// iOS 18's live-updating `SystemFormatStyle.Stopwatch` has no hours-and-minutes clock: dropping
/// the seconds field turns it into words ("1 hour, 23 minutes"), and it leaves the hours field out
/// until an hour has passed (pinned by `SinceLastFeedFormatTests`). So the view draws a clock that
/// still has seconds and clips them off:
/// - First hour: "00:" + a ticking "mm:ss" → "00:05:12", drawn as "00:05".
/// - After that: a ticking "hh:mm:ss" → "01:23:45", drawn as "01:23".
///
/// The content's stale date is the hour mark (`ContentState.sinceLastFeedHourMark`), which makes
/// the system redraw the activity then and switch phase without the app running.
enum SinceLastFeedFormat {
    /// Sizes the visible part: the clock is clipped to this text's width.
    static let visibleTemplate = "00:00"
    /// The ":ss" the clip hides.
    static let hiddenSuffixLength = 3

    /// Whether to draw the hours phase. `isStale` is the system's signal that the hour mark has
    /// passed since the content was drawn.
    static func showsHours(since lastFeedEnded: Date, isStale: Bool, now: Date = .now) -> Bool {
        isStale || now >= lastFeedEnded.addingTimeInterval(3600)
    }

    /// Static text before the ticking clock: "00:" for the first hour, where the clock has no
    /// hours field.
    static func prefix(showsHours: Bool) -> String {
        showsHours ? "" : "00:"
    }

    /// The ticking clock, seconds included: "mm:ss" for the first hour, then "hh:mm:ss".
    /// It must tick each second: a coarser precision switches the style to words.
    static func clock(since lastFeedEnded: Date, showsHours: Bool) -> SystemFormatStyle.Stopwatch {
        SystemFormatStyle.Stopwatch(
            startingAt: lastFeedEnded,
            showsHours: showsHours,
            maxFieldCount: showsHours ? 3 : 2,
            maxPrecision: .seconds(1)
        )
    }

    /// The full drawn string before clipping, e.g. "00:05:12".
    static func fullText(since lastFeedEnded: Date, at now: Date) -> String {
        let hours = showsHours(since: lastFeedEnded, isStale: false, now: now)
        return prefix(showsHours: hours) + String(clock(since: lastFeedEnded, showsHours: hours).format(now).characters)
    }

    /// What the parent sees at a given moment, e.g. "00:05". For tests.
    static func visibleText(since lastFeedEnded: Date, at now: Date) -> String {
        String(fullText(since: lastFeedEnded, at: now).dropLast(hiddenSuffixLength))
    }
}
