//
//  View+CharacterLimit.swift
//  On Board
//

import SwiftUI

extension View {
    /// Clamps `text` to `limit` characters, trimming any excess as it's typed
    /// or pasted. Shared by every comment-composing surface (the bottom
    /// composer bar, the expanded composer sheet, and editing an existing
    /// comment) so the character cap only has to be right in one place.
    func characterLimited(_ text: Binding<String>, to limit: Int) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            guard newValue.count > limit else { return }
            text.wrappedValue = String(newValue.prefix(limit))
        }
    }
}
