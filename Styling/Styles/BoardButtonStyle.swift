//
//  BoardButtonStyle.swift
//  On Board
//
//  Reusable button look used for primary CTAs throughout the app
//  (post composer, save / cancel, etc.). Variants are exposed via
//  `.boardPrimary`, `.boardSecondary`, `.boardDestructive`, and the
//  tone-aware factory `.boardPrimary(tone:)`.
//
//  PrimitiveButtonStyle, not ButtonStyle: the press ripple needs to own the
//  entire tap gesture (see PressRipple.swift's header for why layering a
//  second gesture on top of SwiftUI's automatic Button gesture proved
//  unreliable). PressRippleModifier calls `configuration.trigger()` itself.
//

import SwiftUI

struct BoardButtonStyle: PrimitiveButtonStyle {
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
            .modifier(PressRippleModifier(color: rippleColor, isEnabled: isEnabled, onTrigger: configuration.trigger))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule(style: .continuous))
    }

    private var accent: Color {
        tone?.color ?? .primary
    }

    /// The mid-stop of the ripple's clear → color → clear radial gradient.
    /// Keyed to the variant's background, not the color scheme: a primary
    /// button is dark-on-light in light mode, so its glow must be light.
    /// Pitched a shade stronger than a flat overlay would need, since a
    /// radial gradient's peak fades on both sides rather than sitting flat.
    private var rippleColor: Color {
        switch variant {
        case .primary:
            Color(uiColor: .systemBackground).opacity(0.38)
        case .destructive:
            Color.white.opacity(0.38)
        case .secondary:
            scheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.13)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .destructive: Color(uiColor: .systemBackground)
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
            if #available(iOS 26.0, *) {
                // .interactive() so the glass responds to the press, matching
                // the reaction pills — the primary CTA stays solid on purpose.
                Color.clear
                    .glassEffect(.regular.interactive(), in: shape)
                    .overlay(shape.stroke(accent.opacity(0.45), lineWidth: 1))
            } else {
                shape.fill(.thinMaterial)
                    .overlay(shape.stroke(accent.opacity(0.45), lineWidth: 1))
            }
        case .destructive:
            shape.fill(Color.red)
        }
    }
}

extension PrimitiveButtonStyle where Self == BoardButtonStyle {
    static var boardPrimary: BoardButtonStyle { BoardButtonStyle(variant: .primary) }
    static var boardSecondary: BoardButtonStyle { BoardButtonStyle(variant: .secondary) }
    static var boardDestructive: BoardButtonStyle { BoardButtonStyle(variant: .destructive) }
}
