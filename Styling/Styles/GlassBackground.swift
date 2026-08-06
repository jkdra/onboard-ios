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

    // The remote kill switch (`flag_glassEffects`). Honored here so the flag
    // covers every surface routed through this primitive — before this read,
    // only the four hand-rolled #available sites obeyed it, and pulling the
    // switch mid-incident would have produced a half-glass app that no one
    // had ever seen. Preview-safe: the key defaults to true.
    @Environment(\.glassEffectsEnabled) private var glassEnabled

    var body: some View {
        if #available(iOS 26.0, *), glassEnabled {
            Color.clear.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            shape.fill(fallback)
        }
    }
}
