//
//  BoardTextFieldStyle.swift
//  On Board
//
//  Glass-backed text input, the app's "you can touch this" material.
//
//  Variants:
//  - `.boardStandard` — freestanding form fields (sign-in, onboarding). Sets
//    its own body typography and boxy padding, exactly like the old `.board`.
//  - `.boardTitle` / `.boardBody` / `.boardUsername` — WYSIWYG inline editing
//    (post edit, profile edit). These impose NO typography — the call site
//    keeps its context-matched font so the text edits exactly as it displays —
//    and their glass uses a padding sandwich (pad in, negate out) so the
//    field's layout footprint is identical to the Text it replaces.
//
//  Standard views only: inside Form/List rows the system chrome owns the
//  background — don't fight it with glass panels.
//
//  Focus flair: gaining focus pops a quick bubble (subtle scale overshoot +
//  sheen) — with Reduce Motion, just a brief overlay flash, no movement.
//

import SwiftUI

struct BoardTextFieldStyle: TextFieldStyle {
    enum Variant {
        /// Freestanding form field: imposes body type, full padding box.
        case standard
        /// Inline WYSIWYG for large headings (post title, display name).
        case title
        /// Inline WYSIWYG for body copy (post description, bio).
        case body
        /// Inline WYSIWYG for the handle — compact chrome; the call site bumps
        /// the font above display size on purpose (a subheadline-sized target
        /// is miserable for precision editing).
        case username
    }

    var variant: Variant = .standard

    func _body(configuration: TextField<Self._Label>) -> some View {
        GlassFieldChrome(variant: variant) {
            if variant == .standard {
                configuration.fontStyle(.body)
            } else {
                configuration
            }
        }
    }
}

/// Owns the focus tracking and flash state — kept as a real View so
/// `@FocusState` and friends are guaranteed to behave.
private struct GlassFieldChrome<Content: View>: View {
    let variant: BoardTextFieldStyle.Variant
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var isFocused: Bool
    @State private var flashOpacity: Double = 0
    @State private var bubbleScale: CGFloat = 1
    /// Horizontal position of the focus shimmer band, in unit space. Parked
    /// outside [0, 1] the gradient collapses to clear; sweeping -0.4 → 1.4
    /// passes the band leading-to-trailing across the field once.
    @State private var shimmerPhase: CGFloat = -0.4

    private var cornerRadius: CGFloat {
        switch variant {
        case .standard: 14
        case .title: 16
        case .body: 14
        case .username: 12
        }
    }

    private var inset: (h: CGFloat, v: CGFloat) { variant.inset }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Specular in dark mode; a soft shadow-sheen in light, where a white
    /// band would vanish against the bright glass.
    private var shimmerColor: Color {
        scheme == .dark ? .white.opacity(0.40) : .black.opacity(0.07)
    }

    var body: some View {
        content
            .focused($isFocused)
            .padding(.horizontal, inset.h)
            .padding(.vertical, inset.v)
            .background {
                GlassBackground(shape: shape, fallback: AnyShapeStyle(.thinMaterial))
            }
            .overlay(
                shape.stroke(
                    Color.secondary.opacity(scheme == .dark ? 0.34 : 0.24),
                    lineWidth: 1.2
                )
            )
            .overlay(
                // One-shot focus shimmer, same gesture as the progress bar's
                // glint. Parked off-range this renders fully clear.
                shape.fill(
                    LinearGradient(
                        colors: [.clear, shimmerColor, .clear],
                        startPoint: UnitPoint(x: shimmerPhase - 0.3, y: 0.35),
                        endPoint: UnitPoint(x: shimmerPhase + 0.3, y: 0.65)
                    )
                )
                .allowsHitTesting(false)
            )
            .overlay(
                // Reduce Motion replacement: a brief static sheen, no movement.
                shape.fill(shimmerColor)
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
            )
            .scaleEffect(bubbleScale)
            // No layout compensation: panels occupy their real space, so the
            // stack spacings around them are visually true — uneven "secret
            // bleed" gaps were the source of the edit-mode rhythm problems
            // (and a two-phase layout settle that made fields jump).
            .onChange(of: isFocused) { _, focused in
                guard focused else { return }
                flash()
            }
    }

    private func flash() {
        guard !reduceMotion else {
            flashOpacity = 1
            withAnimation(.easeOut(duration: 0.45)) { flashOpacity = 0 }
            return
        }
        shimmerPhase = -0.4
        withAnimation(.easeOut(duration: 0.65)) { shimmerPhase = 1.4 }
        withAnimation(.easeOut(duration: 0.12)) { bubbleScale = 1.02 }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.55).delay(0.12)) {
            bubbleScale = 1
        }
    }
}

extension BoardTextFieldStyle.Variant {
    /// Inner glass padding. Single source of truth — `GlassFieldChrome` pads
    /// by it, `matchedFieldText(id:in:variant:)` negates by it to register the
    /// text frame instead of the glass frame. Keep inline insets modest — the
    /// bleed comes out of the surrounding margins, and panels that reach the
    /// screen edge read as slabs, not field chrome.
    var inset: (h: CGFloat, v: CGFloat) {
        switch self {
        case .standard: (18, 16)
        case .title: (12, 10)
        case .body: (12, 10)
        case .username: (10, 7)
        }
    }
}

extension View {
    /// `matchedGeometryEffect` for a glass field that registers the *text*
    /// frame, not the glass frame. The styled field is padded inward by the
    /// variant's inset, so negating that inset yields a frame congruent with
    /// the text itself (the glass overflows it symmetrically). Paired with a
    /// plain `Text` on the read side, the edit-mode morph slides the text
    /// inward to its inset position as the chrome appears — instead of
    /// crossfading two copies offset by one inset. Runs entirely inside the
    /// caller's `withAnimation` transaction; no two-phase settle.
    func matchedFieldText(
        id: some Hashable,
        in namespace: Namespace.ID,
        variant: BoardTextFieldStyle.Variant,
        anchor: UnitPoint = .leading
    ) -> some View {
        let inset = variant.inset
        return self
            .padding(.horizontal, -inset.h)
            .padding(.vertical, -inset.v)
            .matchedGeometryEffect(id: id, in: namespace, anchor: anchor)
            .padding(.horizontal, inset.h)
            .padding(.vertical, inset.v)
    }
}

extension TextFieldStyle where Self == BoardTextFieldStyle {
    static var boardStandard: BoardTextFieldStyle { BoardTextFieldStyle(variant: .standard) }
    static var boardTitle: BoardTextFieldStyle { BoardTextFieldStyle(variant: .title) }
    static var boardBody: BoardTextFieldStyle { BoardTextFieldStyle(variant: .body) }
    static var boardUsername: BoardTextFieldStyle { BoardTextFieldStyle(variant: .username) }
}
