//
//  View+ToolbarLabel.swift
//  On Board
//
//  Shared treatment for the action buttons in the edit / compose toolbars
//  (post editing, profile editing, post making): show both the title and the icon,
//  rendered in the app's custom font rather than the system default.
//

import SwiftUI

extension View {
    /// Apply to a `Label` inside a toolbar action button so it shows title + icon
    /// in the app's custom font.
    ///
    /// TODO: Currently a no-op in the navigation bar — SwiftUI toolbar buttons override
    /// `labelStyle`/`fontStyle`, so neither the title+icon display nor the custom font
    /// take effect there. Revisit with a custom toolbar label view (or `ToolbarItem`
    /// styling) to actually surface the title + Zalando font on these action buttons.
    func toolbarActionLabel() -> some View {
        labelStyle(.titleAndIcon)
            .fontStyle(.body)
    }
}
