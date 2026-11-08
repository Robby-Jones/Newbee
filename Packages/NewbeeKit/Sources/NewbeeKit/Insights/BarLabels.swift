import Foundation

/// Which numbers the Insights bar charts print, so labels stay readable however many bars there
/// are. Every bar with something in it gets its total on top. A stacked segment gets its own
/// value inside only when the bars are wide enough, the bar has more than one segment (otherwise
/// the total already says it), and the segment is tall enough to hold the text.
public enum BarLabels {
    /// How much room each bar has, from the number of bars in the chart.
    public enum Density: Sendable, Hashable {
        /// Up to 8 bars (7 d): regular labels.
        case roomy
        /// Up to 16 bars (14 d): smaller labels.
        case compact
        /// More (24 h, 30 d): tiny totals only, no segment labels.
        case dense
    }

    public static func density(barCount: Int) -> Density {
        switch barCount {
        case ...8: .roomy
        case ...16: .compact
        default: .dense
        }
    }

    /// Smallest segment, as a share of the tallest bar, that gets a label inside it.
    public static let minimumSegmentShare = 0.18

    /// Whether the segment worth `value` in a bar made of `segments` gets its own label, when the
    /// tallest bar in the chart is `tallest`.
    public static func showsSegmentLabel(_ value: Double, in segments: [Double], tallest: Double, density: Density) -> Bool {
        guard density != .dense, value > 0, tallest > 0 else { return false }
        guard segments.filter({ $0 > 0 }).count > 1 else { return false }
        return value >= tallest * minimumSegmentShare
    }

    /// Top of the y axis: room above the tallest bar for its total.
    public static func axisTop(tallest: Double) -> Double {
        tallest > 0 ? tallest * 1.18 : 1
    }
}
