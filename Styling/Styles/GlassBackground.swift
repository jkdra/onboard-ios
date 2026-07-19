//
//  GlassBackground.swift
//  On Board
//
//  Single source for the `if #available(iOS 26.0, *) { glassEffect } else
//  { material fill }` dance that was hand-copied across the composer bar, OTP
//  digit boxes, toasts, glass text fields, and secondary buttons. Each of those
//  sites reimplemented the same availability branch inline; they now share this.
//
//  `interactive` maps to `.regular.interactive()` (the glass reacts to touch) —
//  leave it off for static chrome. `fallback` is the pre-26 fill; pass whatever
//  material/color the site used before (`.thinMaterial`, `.regularMaterial`, a
//  translucent systemBackground, …) so nothing changes visually on iOS 18–25.
//
//  Deliberately NOT used by ReactionBar: its glass is selection-aware and
//  tone-tinted (`.regular.tint(tone).interactive()`), which is reaction-specific
//  and stays local rather than bloating this primitive's surface.
//

import SwiftUI

struct GlassBackground<S: Shape>: View {
    let shape: S
    var interactive: Bool = false
    var fallback: AnyShapeStyle = AnyShapeStyle(.regularMaterial)

    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            shape.fill(fallback)
        }
    }
}
