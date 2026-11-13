import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Puts the keyboard away, whichever field has focus.
@MainActor
func dismissKeyboard() {
    #if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

/// Lets the keyboard be put away in forms with multi-line fields (where Return adds a new line):
/// a Done button above the keyboard, and dragging the content down.
struct KeyboardDismissable: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }.fontWeight(.semibold)
                }
            }
            #endif
    }
}

extension View {
    func keyboardDismissable() -> some View { modifier(KeyboardDismissable()) }
}
