#if canImport(UIKit)
import SwiftUI
import UIKit

/// Adds a keyboard-accessory toolbar with a trailing "Done" button that resigns first responder.
/// Use on any Form/TextField-heavy view so keyboard dismissal is consistent.
struct DSKeyboardDismissToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

extension View {
    func dsKeyboardDismissToolbar() -> some View {
        modifier(DSKeyboardDismissToolbar())
    }
}
#endif
