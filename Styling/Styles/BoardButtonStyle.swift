//
//  BoardButtonStyle.swift
//  On Board
//
//  Reusable button look used for primary CTAs throughout the app
//  (post composer, save / cancel, etc.). Variants are exposed via
//  `.boardPrimary`, `.boardSecondary`, `.boardDestructive`, and the
//  tone-aware factory `.boardPrimary(tone:)`.
//

import SwiftUI

struct BoardButtonStyle: ButtonStyle {
    enum Variant {
        case primary, secondary, destructive
    }

    var variant: Variant = .primary
    var tone: PostTone? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontStyle(.headline)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(background)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule(style: .continuous))
    }

    private var accent: Color {
        tone?.color ?? .accentColor
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .destructive: .white
        case .secondary: .primary
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = Capsule(style: .continuous)
        switch variant {
        case .primary:
            shape.fill(accent)
        case .secondary:
            shape.fill(.thinMaterial)
                .overlay(shape.stroke(accent.opacity(0.45), lineWidth: 1))
        case .destructive:
            shape.fill(Color.red)
        }
    }
}

extension ButtonStyle where Self == BoardButtonStyle {
    static var boardPrimary: BoardButtonStyle { BoardButtonStyle(variant: .primary) }
    static var boardSecondary: BoardButtonStyle { BoardButtonStyle(variant: .secondary) }
    static var boardDestructive: BoardButtonStyle { BoardButtonStyle(variant: .destructive) }

    static func boardPrimary(tone: PostTone) -> BoardButtonStyle {
        BoardButtonStyle(variant: .primary, tone: tone)
    }

    static func boardSecondary(tone: PostTone) -> BoardButtonStyle {
        BoardButtonStyle(variant: .secondary, tone: tone)
    }
}
