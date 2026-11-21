import SwiftUI
import UIKit

extension View {
    /// Adds a "Done" button above the keyboard that dismisses it, whichever field is being typed in.
    ///
    /// Fields keep their own focus state (the notes box in `NotesEditor` has a private one), so the
    /// button resigns the first responder instead of clearing one sheet's focus binding. Clearing
    /// only the sheet's binding left the keyboard up while a note was being typed.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("keyboard.done")
            }
        }
    }
}

/// Dismisses the keyboard from any text field on screen.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
