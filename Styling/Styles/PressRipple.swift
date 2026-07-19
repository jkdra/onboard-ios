//
//  PressRipple.swift
//  On Board
//
//  Touch ripple for board buttons. Owns the ENTIRE press interaction —
//  BoardButtonStyle is a PrimitiveButtonStyle, not a ButtonStyle, precisely
//  so there is only ever one gesture recognizer on a board button, not two
//  arguing over the same touch. (A second gesture layered on top of
//  SwiftUI's automatic Button gesture — even `.simultaneousGesture` with
//  only `.onChanged` — proved unreliable in practice: on device it silently
//  suppressed the button's own action while the ripple kept animating,
//  since `configuration.isPressed` is SwiftUI's own signal and doesn't
//  reflect whether the tap actually completed.) Here, we recognize the
//  gesture and call `configuration.trigger()` ourselves — there's nothing
//  left to compete with.
//
//  Three-phase choreography:
//    · finger down  — a radial glow blooms from the touch point and parks at
//                     ~65%, its center tracking the finger while held
//    · release      — completes outward and dissolves, then fires the action
//    · cancel       — retreats back into the origin (finger slid off before
//                     lifting), signalling "nothing happened"
//
//  Reduce Motion swaps the glow for a static sheen while pressed, but the
//  tap itself is still fully recognized — only the visuals are skipped.
//
//  Accessibility note: VoiceOver / Switch Control / Full Keyboard Access
//  invoke `configuration.trigger()` directly via the Button's synthesized
//  accessibility action, bypassing this gesture entirely — activation keeps
//  working from those technologies even though no ripple plays for them.
//

import SwiftUI

struct PressRippleModifier: ViewModifier {
    var color: Color
    var isEnabled: Bool
    var onTrigger: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    private enum Phase { case idle, holding, finishing }

    @State private var phase: Phase = .idle
    @State private var origin: CGPoint = .zero
    @State private var size: CGSize = .zero
    @State private var progress: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    @State private var isPressedVisual = false
    @State private var hapticTick = 0

    func body(content: Content) -> some View {
        content
            // Forces the WHOLE button — including a transparent/glass
            // background (e.g. .boardSecondary's Color.clear base) — to be
            // hit-testable, so the gesture below isn't silently scoped to
            // just the label's rendered glyphs.
            .contentShape(Capsule(style: .continuous))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .overlay {
                rippleVisual
                    .clipShape(Capsule(style: .continuous))
                    .allowsHitTesting(false)
            }
            .scaleEffect(isPressedVisual ? 0.97 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isPressedVisual)
            .gesture(
                // The button's ONLY gesture — see the file header. Zero
                // minimum distance so it recognizes from touch-down, the
                // same trigger condition a tap has.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        if phase == .idle {
                            begin(at: value.location)
                        } else if phase == .holding {
                            // The glow's center follows the finger.
                            origin = value.location
                        }
                    }
                    .onEnded { value in
                        guard isEnabled, phase == .holding else { return }
                        let completed = tapBounds.contains(value.location)
                        finish(completed: completed)
                        if completed { onTrigger() }
                    }
            )
            .sensoryFeedback(trigger: hapticTick) { _, _ in
                hapticsEnabled ? .impact(weight: .light) : nil
            }
    }

    @ViewBuilder
    private var rippleVisual: some View {
        if reduceMotion {
            // Static sheen — acknowledgement without movement.
            Capsule(style: .continuous)
                .fill(color)
                .opacity(isPressedVisual ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: isPressedVisual)
        } else {
            // clear → color → clear: no ring/circle boundary ever exists,
            // since both edges of the gradient are fully transparent — the
            // glow just fades into the glass rather than being clipped off.
            RadialGradient(
                colors: [.clear, color, .clear],
                center: unitOrigin,
                startRadius: 0,
                endRadius: maxRadius * progress
            )
            .opacity(rippleOpacity)
        }
    }

    private var unitOrigin: UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: origin.x / size.width, y: origin.y / size.height)
    }

    /// Distance from the (moving) origin to the farthest corner — the radius
    /// at which progress 1 guarantees the glow has swept the entire button.
    private var maxRadius: CGFloat {
        let dx = max(origin.x, size.width - origin.x)
        let dy = max(origin.y, size.height - origin.y)
        return sqrt(dx * dx + dy * dy)
    }

    /// A little forgiveness past the visible bounds — a finger lifting just
    /// outside the capsule still counts as a tap, matching the generous
    /// touch targets standard UIKit controls give you.
    private var tapBounds: CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: -24, dy: -24)
    }

    private func begin(at location: CGPoint) {
        origin = location
        phase = .holding
        isPressedVisual = true
        hapticTick += 1
        if reduceMotion {
            rippleOpacity = 0  // reduceMotion's visual is driven by isPressedVisual, not this
        } else {
            progress = 0.08
            rippleOpacity = 1
            withAnimation(.easeOut(duration: 0.4)) { progress = 0.65 }
        }
    }

    private func finish(completed: Bool) {
        phase = .finishing
        isPressedVisual = false

        guard !reduceMotion else {
            phase = .idle
            return
        }

        if completed {
            withAnimation(.easeOut(duration: 0.32)) { progress = 1 }
            withAnimation(.easeOut(duration: 0.28).delay(0.06)) { rippleOpacity = 0 }
        } else {
            withAnimation(.easeIn(duration: 0.22)) {
                progress = 0
                rippleOpacity = 0
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            if phase == .finishing {
                phase = .idle
                progress = 0
            }
        }
    }
}
