import NewbeeShared
import SwiftUI

/// Large stopwatch numerals: rounded, monospaced digits, scaling with Dynamic Type.
/// The value is always derived from timestamps by the caller; this view only formats it.
struct TimerText: View {
    let duration: TimeInterval
    @ScaledMetric private var size: CGFloat

    init(_ duration: TimeInterval, size: CGFloat = 64, relativeTo textStyle: Font.TextStyle = .largeTitle) {
        self.duration = duration
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        Text(DurationText.clock(duration))
            .font(NBFont.timer(size: size))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(DurationText.spoken(duration))
    }
}

#Preview {
    VStack {
        TimerText(18 * 60 + 42)
        TimerText(12 * 60 + 5, size: 34, relativeTo: .title)
        TimerText(3_723, size: 17, relativeTo: .body)
    }
}
