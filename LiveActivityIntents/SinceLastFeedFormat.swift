// Compiled into both the app and the widget extension (like the intents in this folder), so the
// app's tests check the exact formats the Live Activity renders.

import Foundation
import SwiftUI

/// The since-last-feed count on the Live Activity, as a ticking `h:mm` clock: "0:05", "0:45",
/// "1:23", "12:05".
///
/// The system's live-updating formats (iOS 18 `SystemFormatStyle`) drop the hours field until an
/// hour has passed, so they can't show "0:45" on their own. The count is drawn in two phases:
/// - First hour: a static "0:" before a ticking two-digit minutes field.
/// - After that: a ticking hours-and-minutes clock.
///
/// The content's stale date is the hour mark (`ContentState.sinceLastFeedHourMark`), which makes
/// the system redraw the activity then and switch phase without the app running.
enum SinceLastFeedFormat {
    /// Whether to draw the hours-and-minutes phase. `isStale` is the system's signal that the hour
    /// mark has passed since the content was drawn.
    static func showsHours(since lastFeedEnded: Date, isStale: Bool, now: Date = .now) -> Bool {
        isStale || now >= lastFeedEnded.addingTimeInterval(3600)
    }

    /// Minutes only, zero-padded ("05", "45"), for the first hour.
    static func minutes(since lastFeedEnded: Date) -> SystemFormatStyle.Stopwatch {
        SystemFormatStyle.Stopwatch(startingAt: lastFeedEnded, showsHours: false, maxFieldCount: 1, maxPrecision: .seconds(1))
    }

    /// Hours and minutes ("1:23", "12:05"), once an hour has passed.
    static func hoursAndMinutes(since lastFeedEnded: Date) -> SystemFormatStyle.Stopwatch {
        SystemFormatStyle.Stopwatch(startingAt: lastFeedEnded, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1))
    }

    /// The same text the views draw, at a given moment. For tests and VoiceOver.
    static func text(since lastFeedEnded: Date, at now: Date) -> String {
        if showsHours(since: lastFeedEnded, isStale: false, now: now) {
            return String(hoursAndMinutes(since: lastFeedEnded).format(now).characters)
        }
        return "0:" + String(minutes(since: lastFeedEnded).format(now).characters)
    }
}
