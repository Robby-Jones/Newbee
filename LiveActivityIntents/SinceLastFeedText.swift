// Compiled into both the app and the widget extension (like the intents in this folder), so the
// app's tests can render the exact view the Live Activity draws.

import Foundation
import SwiftUI

/// Time since the last feed ended, as a stopwatch the system ticks: "4:12", then "2:15:03".
///
/// This is the same `Text(timerInterval:)` the side pills and the feeding total use, which draws
/// correctly on the Lock Screen. Two earlier ways of showing `hh:mm` without seconds (a clock
/// with its seconds clipped off) measured fine in tests but drew shifted on a real Lock Screen
/// (")0:04:"), because the system lays out a live date text at its own width and position. iOS
/// has no live format that shows hours and minutes as digits without seconds, so a seconds-free
/// count would need the app or a push server to update the activity every minute.
///
/// Like every live timer text it takes all the width it's offered and centers itself, so callers
/// set `.multilineTextAlignment` and a `.frame(maxWidth:alignment:)`.
struct SinceLastFeedText: View {
    let lastFeedEnded: Date

    var body: some View {
        Text(timerInterval: lastFeedEnded...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Time since last feed"))
            .accessibilityValue(Text(lastFeedEnded, style: .relative))
    }
}
