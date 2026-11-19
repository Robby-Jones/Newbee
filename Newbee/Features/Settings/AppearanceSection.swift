import NewbeeShared
import SwiftUI
import UIKit

/// Settings → Appearance (docs/UX_SPEC.md §2.1): light or dark, the color theme (indigo or pink)
/// and the app icon (sky-blue or pink bee). The color theme and the icon are this phone's only.
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
            AppIconRow()
        }
    }
}

extension NBTheme {
    var title: String {
        switch self {
        case .standard: String(localized: "Indigo")
        case .pink: String(localized: "Pink")
        }
    }

    /// The swatch in Settings: the theme's accent, drawn the same in either mode so the two
    /// choices always look like themselves.
    var swatch: Color {
        switch self {
        case .standard: Color(light: 0x5054C2, dark: 0x8E91F0)
        case .pink: Color(light: 0xE97DAE, dark: 0xE97DAE)
        }
    }

    var accessibilityIdentifier: String { "settings.theme.\(rawValue)" }
}

/// "Color" with a round swatch per theme; the picked one has a ring and a check.
private struct ThemeSwatchRow: View {
    @Binding var selection: NBTheme

    var body: some View {
        HStack {
            Text("Color")
            Spacer()
            HStack(spacing: NBSpacing.m) {
                ForEach(NBTheme.allCases) { theme in
                    Button {
                        selection = theme
                    } label: {
                        Circle()
                            .fill(theme.swatch)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if selection == theme {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(3)
                            .overlay(Circle().strokeBorder(selection == theme ? theme.swatch : .clear, lineWidth: 2))
                            .frame(minWidth: NBLayout.minHitTarget, minHeight: NBLayout.minHitTarget)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.title)
                    .accessibilityAddTraits(selection == theme ? .isSelected : [])
                    .accessibilityIdentifier(theme.accessibilityIdentifier)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The home screen icon: the sky-blue bee, or the same bee on pink.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard
    case pink

    var id: String { rawValue }

    /// The name iOS knows the icon by (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in
    /// project.yml); `nil` is the primary icon.
    var alternateIconName: String? {
        switch self {
        case .standard: nil
        case .pink: "AppIcon-Pink"
        }
    }

    /// A small copy of the icon for the picker (asset catalogs don't expose app icons as images).
    var previewImageName: String {
        switch self {
        case .standard: "IconPreview"
        case .pink: "IconPreview-Pink"
        }
    }

    var title: String {
        switch self {
        case .standard: String(localized: "Blue bee icon")
        case .pink: String(localized: "Pink bee icon")
        }
    }

    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .standard
    }
}

/// "App icon" with a thumbnail per icon. iOS shows its own "You have changed the icon" alert.
private struct AppIconRow: View {
    @State private var selection = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            HStack {
                Text("App icon")
                Spacer()
                HStack(spacing: NBSpacing.m) {
                    ForEach(AppIconChoice.allCases) { icon in
                        Button {
                            choose(icon)
                        } label: {
                            Image(icon.previewImageName)
                                .resizable()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(selection == icon ? NBColor.accent : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.title)
                        .accessibilityAddTraits(selection == icon ? .isSelected : [])
                        .accessibilityIdentifier("settings.appIcon.\(icon.rawValue)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func choose(_ icon: AppIconChoice) {
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
