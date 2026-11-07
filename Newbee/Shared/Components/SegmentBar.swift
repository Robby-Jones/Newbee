import NewbeeKit
import NewbeeShared
import SwiftUI

/// Horizontal bar showing the left/right split of a breastfeeding session.
struct SegmentBar: View {
    let left: TimeInterval
    let right: TimeInterval
    var height: CGFloat = 8

    var body: some View {
        let total = max(left + right, 0)
        GeometryReader { proxy in
            let gap: CGFloat = (left > 0 && right > 0) ? 2 : 0
            let available = max(0, proxy.size.width - gap)
            let leftWidth = total > 0 ? available * left / total : 0
            HStack(spacing: gap) {
                if left > 0 {
                    Capsule().fill(NBColor.left).frame(width: leftWidth)
                }
                if right > 0 {
                    Capsule().fill(NBColor.right)
                }
                if total == 0 {
                    Capsule().fill(Color.secondary.opacity(0.2))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Left \(DurationText.spoken(left)), right \(DurationText.spoken(right))"))
    }
}

#Preview {
    VStack(spacing: 12) {
        SegmentBar(left: 12 * 60, right: 9 * 60)
        SegmentBar(left: 20 * 60, right: 0)
        SegmentBar(left: 0, right: 0)
    }
    .padding()
}
