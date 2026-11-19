import NewbeeShared
import SwiftUI

/// A Settings section header with a subtle info button after the title. Tapping it shows what the
/// section does in a small popover, so the list stays short. Footers are kept for live status and
/// warnings only (docs/UX_SPEC.md §3.10).
struct SettingsSectionHeader: View {
    let title: LocalizedStringKey
    let info: String
    /// For UI tests: `settings.info.<identifier>`.
    let identifier: String

    @State private var isShowingInfo = false

    init(_ title: LocalizedStringKey, info: String, identifier: String) {
        self.title = title
        self.info = info
        self.identifier = identifier
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .imageScale(.medium)
                    .foregroundStyle(NBColor.secondaryText)
                    // A bigger tap target than the glyph without moving it.
                    .padding(8)
                    .contentShape(Rectangle())
                    .padding(-8)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("About \(Text(title))"))
            .accessibilityIdentifier("settings.info.\(identifier)")
            .popover(isPresented: $isShowingInfo, arrowEdge: .bottom) {
                Text(info)
                    .font(.subheadline)
                    .textCase(nil)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 280, alignment: .leading)
                    .padding(NBSpacing.l)
                    .presentationCompactAdaptation(.popover)
                    .accessibilityIdentifier("settings.infoText")
            }
        }
    }
}
