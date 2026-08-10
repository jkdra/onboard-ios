//
//  EditModeToolbarItems.swift
//  On Board
//
//  The shared edit-mode toolbar trio: ✕ cancel (leading), the animated
//  EditingIndicator (principal), ✓ save (trailing). Used by both profile
//  editing and post editing so the two modes stay visually identical;
//  callers append their own extra items (e.g. the post editor's bottom-bar
//  tone picker) alongside this.
//

import SwiftUI

struct EditModeToolbarItems: ToolbarContent {
    var canSave: Bool = true
    var saveTint: Color? = nil
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { onCancel() } label: {
                Label("Cancel", systemImage: "xmark").fontWeight(.semibold)
            }
        }
        // No EDITING… indicator: the X/✓ chrome and morphed fields already
        // say it, and the principal slot is better spent by the host screen
        // (post edit puts the tone picker there, matching NewPostView).
        ToolbarItem(placement: .topBarTrailing) {
            Button { onSave() } label: {
                Label("Save", systemImage: "checkmark").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(saveTint)
            .disabled(!canSave)
        }
    }
}
