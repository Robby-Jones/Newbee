import NewbeeShared
import SwiftUI

/// Soft rounded card: the basic surface of the app (docs/UX_SPEC.md §2).
/// Light mode gets a soft shadow; dark mode gets a hairline border instead.
struct Card<Content: View>: View {
    var padding: CGFloat = NBSpacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nbCardBackground()
    }
}

extension View {
    /// The card surface without padding, for custom layouts.
    func nbCardBackground(cornerRadius: CGFloat = NBRadius.card) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

private struct CardBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(NBColor.card, in: shape)
            .overlay {
                if colorScheme == .dark {
                    shape.strokeBorder(NBColor.hairline, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 4, y: 2)
    }
}

#Preview {
    VStack {
        Card {
            Text("Last feed").font(.headline)
            Text("2 h 14 min ago").foregroundStyle(NBColor.secondaryText)
        }
    }
    .padding()
    .background(NBColor.canvas)
}
