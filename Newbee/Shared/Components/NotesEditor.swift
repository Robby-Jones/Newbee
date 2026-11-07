import NewbeeShared
import SwiftUI

/// A roomy notes box with one-tap tags (docs/UX_SPEC.md §3.7).
///
/// Notes get real space, like a journal entry, instead of a one-line field: the box shows several
/// lines before the parent types anything, and common observations are one tap away.
struct NotesEditor: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey = "How did it go? Latch, fussiness, spit-up…"
    var tags: [String] = NotesEditor.breastTags
    /// Lines of space shown before any text is typed.
    var minLines = 5
    /// Accessibility identifier for the text field (UI tests).
    var fieldIdentifier = "notes.field"

    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 22

    static let breastTags = [
        String(localized: "Sleepy"), String(localized: "Fussy"), String(localized: "Good latch"),
        String(localized: "Spit up"), String(localized: "Hiccups"),
    ]
    static let bottleTags = [
        String(localized: "Finished it"), String(localized: "Left some"), String(localized: "Spit up"),
        String(localized: "Fussy"), String(localized: "Sleepy"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: NBSpacing.m) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(minLines...12)
                .focused($focused)
                .frame(minHeight: CGFloat(minLines) * lineHeight, alignment: .topLeading)
                .contentShape(Rectangle())
                // The whole box is the tap target, not just the first line.
                .onTapGesture { focused = true }
                .accessibilityIdentifier(fieldIdentifier)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NBSpacing.s) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(title: tag, isSelected: Self.contains(tag, in: text)) {
                                text = Self.toggling(tag, in: text)
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    /// Whether `tag` already appears in `text`, ignoring case.
    static func contains(_ tag: String, in text: String) -> Bool {
        text.range(of: tag, options: .caseInsensitive) != nil
    }

    /// Adds `tag` to the end of the note, or removes it if it's already there.
    static func toggling(_ tag: String, in text: String) -> String {
        if let range = text.range(of: tag, options: .caseInsensitive) {
            var result = text
            result.removeSubrange(range)
            // Tidy the separator left behind ("Sleepy, , Fussy" → "Sleepy, Fussy").
            while result.contains(", ,") { result = result.replacingOccurrences(of: ", ,", with: ",") }
            return result.trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespacesAndNewlines))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return tag }
        let endsSentence = trimmed.last.map { ".!?".contains($0) } ?? false
        return trimmed + (endsSentence ? " " : ", ") + tag
    }
}

/// A one-tap tag, at least 36 pt tall inside a 44 pt row.
private struct TagChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, NBSpacing.m)
                .frame(minHeight: 36)
                .background(Capsule().fill(NBColor.accent.opacity(isSelected ? 0.28 : 0.1)))
                .overlay {
                    if isSelected {
                        Capsule().strokeBorder(NBColor.accent, lineWidth: 1.5)
                    }
                }
                .foregroundStyle(Color.primary)
                .frame(minHeight: NBLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? Text("Removes it from the note") : Text("Adds it to the note"))
    }
}

private struct NotesEditorPreview: View {
    @State var text = "Sleepy"

    var body: some View {
        Form {
            Section("Notes") {
                NotesEditor(text: $text)
            }
        }
    }
}

#Preview {
    NotesEditorPreview()
}
