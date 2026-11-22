import NewbeeShared
import SwiftUI
import UIKit

/// Settings → Appearance (docs/UX_SPEC.md §2.1): light or dark, the color theme, the Live
/// Activity's colors (a page of their own) and the app icon. The color theme, the Live Activity
/// color and the icon are this phone's only.
struct AppearanceSection: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Section("Appearance") {
            Picker("Mode", selection: $preferences.appearance) {
                ForEach(AppPreferences.Appearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            ThemeSwatchRow(selection: $preferences.colorTheme)
            NavigationLink(value: SettingsPage.liveActivityColor) {
                LabeledContent("Live Activity", value: preferences.liveActivityColor.shortTitle)
            }
            .accessibilityIdentifier("settings.liveActivityColor")
            AppIconRow()
        }
    }
}

extension NBTheme {
    var title: String {
        switch self {
        case .standard: String(localized: "Indigo")
        case .pink: String(localized: "Pink")
        case .sage: String(localized: "Sage")
        case .ocean: String(localized: "Ocean")
        case .lavender: String(localized: "Lavender")
        case .peach: String(localized: "Peach")
        }
    }

    /// The swatch in Settings: the theme's soft dark-mode accent, drawn the same in either mode
    /// so each choice always looks like itself. A dark check sits on it.
    var swatch: Color { Color(rgb: colors.accent.dark) }

    /// The name iOS knows this theme's bee icon by (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
    /// in project.yml); `nil` is the primary, sky-blue icon.
    var alternateIconName: String? {
        switch self {
        case .standard: nil
        case .pink: "AppIcon-Pink"
        case .sage: "AppIcon-Sage"
        case .ocean: "AppIcon-Ocean"
        case .lavender: "AppIcon-Lavender"
        case .peach: "AppIcon-Peach"
        }
    }

    /// A small copy of the icon for the picker (asset catalogs don't expose app icons as images).
    var iconPreviewName: String {
        alternateIconName.map { $0.replacingOccurrences(of: "AppIcon", with: "IconPreview") } ?? "IconPreview"
    }

    var iconTitle: String {
        self == .standard ? String(localized: "Blue bee icon") : String(localized: "\(title) bee icon")
    }

    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .standard
    }
}

/// "Color" with a round swatch per theme underneath; the picked one has a ring and a check.
private struct ThemeSwatchRow: View {
    @Binding var selection: NBTheme

    var body: some View {
        VStack(alignment: .leading, spacing: NBSpacing.s) {
            Text("Color")
            HStack(spacing: 0) {
                ForEach(NBTheme.allCases) { theme in
                    Button {
                        selection = theme
                    } label: {
                        Circle()
                            .fill(theme.swatch)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if selection == theme {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(NBColor.onSide)
                                }
                            }
                            .padding(3)
                            .overlay(Circle().strokeBorder(selection == theme ? theme.swatch : .clear, lineWidth: 2))
                            .frame(maxWidth: .infinity, minHeight: NBLayout.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.title)
                    .accessibilityAddTraits(selection == theme ? .isSelected : [])
                    .accessibilityIdentifier("settings.theme.\(theme.rawValue)")
                }
            }
        }
        .padding(.vertical, NBSpacing.xs)
        .accessibilityElement(children: .contain)
    }
}

/// "App icon" with a thumbnail per theme's bee underneath. iOS shows its own "You have changed
/// the icon" alert.
private struct AppIconRow: View {
    @State private var selection = NBTheme(alternateIconName: UIApplication.shared.alternateIconName)

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            VStack(alignment: .leading, spacing: NBSpacing.s) {
                Text("App icon")
                HStack(spacing: 0) {
                    ForEach(NBTheme.allCases) { icon in
                        Button {
                            choose(icon)
                        } label: {
                            Image(icon.iconPreviewName)
                                .resizable()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .padding(3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(selection == icon ? NBColor.accent : .clear, lineWidth: 2)
                                )
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.iconTitle)
                        .accessibilityAddTraits(selection == icon ? .isSelected : [])
                        .accessibilityIdentifier("settings.appIcon.\(icon.rawValue)")
                    }
                }
            }
            .padding(.vertical, NBSpacing.xs)
            .accessibilityElement(children: .contain)
        }
    }

    private func choose(_ icon: NBTheme) {
        guard icon != selection else { return }
        let previous = selection
        selection = icon
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(icon.alternateIconName)
            } catch {
                // Refused (rare, e.g. while the app is going to the background): show what's set.
                selection = previous
            }
        }
    }
}
