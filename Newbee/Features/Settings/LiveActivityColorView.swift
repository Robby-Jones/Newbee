import NewbeeKit
import NewbeeShared
import SwiftData
import SwiftUI
import UIKit

/// Settings → Appearance → Live Activity (docs/UX_SPEC.md §2.1): the Lock Screen card's colors,
/// picked apart from the app's color theme. A preview of the card at the top, then "Match app
/// theme" (the default), Black, and a light and a dark card in each theme's color. Kept on this
/// phone only.
struct LiveActivityColorView: View {
    @Bindable var preferences: AppPreferences

    private var selection: LiveActivityColor { preferences.liveActivityColor }

    var body: some View {
        Form {
            Section {
                LiveActivityColorPreview(color: selection, theme: preferences.colorTheme)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                choiceRow(.matchTheme, subtitle: LiveActivityColor.matching(preferences.colorTheme).title)
                choiceRow(.black, subtitle: nil)
            }
            Section("Light") {
                LiveActivityCardSwatchRow(cards: LiveActivityColor.lightCards, selection: $preferences.liveActivityColor)
            }
            Section {
                LiveActivityCardSwatchRow(cards: LiveActivityColor.darkCards, selection: $preferences.liveActivityColor)
            } header: {
                Text("Dark")
            } footer: {
                Text("The Dynamic Island always stays black. Its + takes this color.")
            }
            Section {
                ForEach(IslandIcon.allCases, id: \.self) { icon in
                    islandIconRow(icon)
                }
            } header: {
                Text("Island icon")
            } footer: {
                Text("Shown next to the time in the minimized Dynamic Island after a feed ends.")
            }
        }
        .navigationTitle("Live Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choiceRow(_ color: LiveActivityColor, subtitle: String?) -> some View {
        Button {
            preferences.liveActivityColor = color
        } label: {
            HStack(spacing: NBSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(color.title)
                        .foregroundStyle(Color.primary)
                    if let subtitle {
                        Text("Now: \(subtitle)")
                            .font(.footnote)
                            .foregroundStyle(NBColor.secondaryText)
                    }
                }
                Spacer()
                if selection == color {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NBColor.accent)
                }
            }
            // Form rows are already at least 44 pt tall; a taller frame made these rows look
            // oversized next to the rest of Settings.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == color ? .isSelected : [])
        .accessibilityIdentifier("settings.liveActivityColor.\(color.rawValue)")
    }
}

extension LiveActivityColorView {
    /// A minimized island with the icon and a sample count, the name, and a check when picked.
    private func islandIconRow(_ icon: IslandIcon) -> some View {
        let isSelected = preferences.islandIcon == icon
        return Button {
            preferences.islandIcon = icon
        } label: {
            HStack(spacing: NBSpacing.m) {
                HStack {
                    IslandIconView(icon: icon, state: Self.islandSampleState, size: 20)
                        .frame(width: 22, height: 22)
                    Spacer(minLength: 0)
                    Text(verbatim: "28:47")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .frame(width: 112, height: 30)
                .background(Capsule().fill(Color.black))
                .environment(\.colorScheme, .dark)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(icon.title)
                        .foregroundStyle(Color.primary)
                    if let subtitle = islandIconSubtitle(icon) {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(NBColor.secondaryText)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NBColor.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.islandIcon.\(icon.rawValue)")
    }

    private func islandIconSubtitle(_ icon: IslandIcon) -> String? {
        switch icon {
        // Read the saved copy here, like the row's icon does: a flag set once in `.task` stayed
        // false on device although the icon showed the photo (2026-11-22).
        case .babyPhoto: LiveActivityAvatar.load() != nil ? nil : String(localized: "No photo yet, so the bee shows")
        case .lastFeed: String(localized: "Breastfeed or bottle, in its color")
        case .bee, .clock: nil
        }
    }

    /// A breastfeed that ended on the right, for the "Last feed" row.
    private static var islandSampleState: FeedingActivityAttributes.ContentState {
        let end = Date.now
        return FeedingActivityAttributes.ContentState(
            status: .ended, currentSide: .right, sessionStart: end.addingTimeInterval(-21 * 60),
            currentSegmentStart: nil, leftAccumulated: 12 * 60, rightAccumulated: 9 * 60,
            pausedAt: end, revision: 1
        )
    }
}

/// A round swatch per card: the card's background with a dot of its "+" color; the picked one
/// has a ring and a check.
private struct LiveActivityCardSwatchRow: View {
    let cards: [LiveActivityColor]
    @Binding var selection: LiveActivityColor

    var body: some View {
        HStack(spacing: 0) {
            ForEach(cards, id: \.self) { card in
                let palette = ActivityPalette.card(card, theme: .standard)
                let isSelected = selection == card
                Button {
                    selection = card
                } label: {
                    Circle()
                        .fill(palette.background)
                        .overlay(Circle().strokeBorder(palette.secondaryText.opacity(0.35), lineWidth: 1))
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(palette.primaryText)
                            } else {
                                Circle().fill(palette.newFeed).frame(width: 12, height: 12)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .padding(3)
                        .overlay(Circle().strokeBorder(isSelected ? NBColor.accent : .clear, lineWidth: 2))
                        .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("settings.liveActivityColor.\(card.rawValue)")
            }
        }
        .padding(.vertical, NBSpacing.xs)
        .accessibilityElement(children: .contain)
    }
}

/// The since-last-feed Live Activity as it will look: the Lock Screen card on a soft wallpaper,
/// and the expanded Dynamic Island under it. Draws the widget's own view
/// (`SinceLastFeedActivityContent`) with the baby's name and photo.
struct LiveActivityColorPreview: View {
    let color: LiveActivityColor
    let theme: NBTheme
    @Environment(\.modelContext) private var modelContext
    @State private var photo: UIImage?
    @State private var babyName = ""
    /// Fixed when the page opens, so the count ticks on from 28 minutes ago.
    @State private var lastFeedEnd = Date.now.addingTimeInterval(-28 * 60)

    var body: some View {
        let card = ActivityPalette.card(color, theme: theme)
        let island = ActivityPalette.island(color, theme: theme)
        VStack(spacing: NBSpacing.m) {
            SinceLastFeedActivityContent(
                state: sampleState, babyName: babyName, since: lastFeedEnd, style: .lockScreen, photo: photo
            )
            // A little tighter than the Lock Screen's 16, so "Last fed: 9:25 PM" fits inside
            // the Settings row's margins as it does on the full-width Lock Screen.
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(card.background))
            .environment(\.activityPalette, card)
            .environment(\.colorScheme, card.colorScheme)
            SinceLastFeedActivityContent(
                state: sampleState, babyName: babyName, since: lastFeedEnd, style: .island, photo: photo
            )
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color.black))
            .environment(\.activityPalette, island)
            .environment(\.colorScheme, .dark)
        }
        .padding(.horizontal, NBSpacing.xs)
        .padding(.vertical, NBSpacing.m)
        .background(
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.78, blue: 0.95), Color(red: 0.95, green: 0.80, blue: 0.70)],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: NBRadius.card, style: .continuous)
        )
        // The "+" opens Home in the real activity; here it's only a picture.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the Live Activity in \(color.card(for: theme).title)")
        .accessibilityIdentifier("settings.liveActivityColor.preview")
        .animation(.easeInOut(duration: 0.2), value: color)
        .task {
            photo = LiveActivityAvatar.load()
            babyName = Baby.primary(in: modelContext)?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    /// A breastfeed that ended on the right: "L 12m · R 9m".
    private var sampleState: FeedingActivityAttributes.ContentState {
        let left: TimeInterval = 12 * 60
        let right: TimeInterval = 9 * 60
        return FeedingActivityAttributes.ContentState(
            status: .ended, currentSide: .right, sessionStart: lastFeedEnd.addingTimeInterval(-(left + right)),
            currentSegmentStart: nil, leftAccumulated: left, rightAccumulated: right,
            pausedAt: lastFeedEnd, revision: 1
        )
    }
}

extension LiveActivityColor {
    var title: String {
        switch self {
        case .matchTheme: String(localized: "Match app theme")
        case .black: String(localized: "Black")
        case .light(let theme): String(localized: "Light \(theme.title)")
        case .dark(let theme): String(localized: "Dark \(theme.title)")
        }
    }

    /// The value next to "Live Activity" in Appearance.
    var shortTitle: String {
        self == .matchTheme ? String(localized: "App theme") : title
    }
}
