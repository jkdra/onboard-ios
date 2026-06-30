//
//  View+KeyboardDismiss.swift
//  On Board
//
//  Shared keyboard-dismissal helpers. Two complementary affordances:
//   • `.keyboardDoneToolbar()` adds a trailing "Done" button to the keyboard
//     accessory bar — an explicit, always-discoverable way to dismiss.
//   • `.dismissesKeyboardOnTap()` lets a tap on empty space resign the keyboard,
//     which most users reach for instinctively. It uses a *simultaneous* tap so
//     it never swallows taps destined for buttons, links, or text fields.
//
//  Both funnel through `KeyboardDismisser.dismiss()`, which resigns the current
//  first responder app-wide, so no per-view `@FocusState` plumbing is required.
//

import SwiftUI
import UIKit

enum KeyboardDismisser {
    /// Resigns whatever is currently first responder (i.e. dismisses the keyboard).
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    /// Adds a trailing "Done" button to the keyboard accessory toolbar.
    /// Apply once per screen that hosts text input (attach to the outermost
    /// scrollable/container view so the button isn't duplicated per field).
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    KeyboardDismisser.dismiss()
                } label: {
                    Text("Done").fontWeight(.semibold)
                        .fontStyle(.body)
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
    }

    /// Dismisses the keyboard when the user taps outside a focused field.
    /// Uses a simultaneous tap so interactive controls keep working.
    func dismissesKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                KeyboardDismisser.dismiss()
            }
        )
    }
}
