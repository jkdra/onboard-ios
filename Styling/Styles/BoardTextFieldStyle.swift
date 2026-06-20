//
//  BoardTextFieldStyle.swift
//  On Board
//
//  Rounded, material-backed text input used by the composer and
//  any future inline editing surfaces. Picks up the app's custom
//  Zalando font via `fontStyle(.body)`.
//

import SwiftUI

struct BoardTextFieldStyle: TextFieldStyle {
    var cornerRadius: CGFloat = 14

    @Environment(\.colorScheme) private var scheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .fontStyle(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(scheme == .dark ? 0.30 : 0.20), lineWidth: 1)
            )
    }
}

extension TextFieldStyle where Self == BoardTextFieldStyle {
    static var board: BoardTextFieldStyle { BoardTextFieldStyle() }
}
