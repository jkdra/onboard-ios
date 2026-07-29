//
//  SkeletonShape.swift
//  On Board
//
//  Loading placeholder: a neutral fill with the app's shimmer sweep drifting
//  across it — the same "something's coming" gesture as the progress bar
//  glint and the text-field focus shimmer. Reduce Motion renders a static
//  fill with no movement.
//
//  Skeletons should mirror the real component's geometry (shape and size), so
//  the loaded content replaces them without any layout shift.
//
//  Driven by `TimelineView(.animation)`, NOT a `repeatForever` animation —
//  every other perpetually-animated component in this folder (
//  SignalLostPlaceholder, FireworksView, AnimatedStripesView,
//  AnimatedLogoBackgroundView) already avoids `repeatForever` for the same
//  documented reason: it keeps the app non-idle and makes XCUITest gestures/
//  assertions flaky. This was the one holdout, and — appearing on nearly
//  every loading screen — the animation most likely to be on-screen during a
//  UI test.
//

import SwiftUI

struct SkeletonShape<S: Shape>: View {
    var shape: S

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let period: Double = 1.4

    private var highlight: Color {
        scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.05)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            // Sawtooth 0→1 over `period`, then an instant reset — matches the
            // old `.linear(...).repeatForever(autoreverses: false)` sweep.
            let progress = (timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period)) / period
            let phase = -0.4 + progress * 1.8

            shape
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [.clear, highlight, .clear],
                            startPoint: UnitPoint(x: phase - 0.3, y: 0.4),
                            endPoint: UnitPoint(x: phase + 0.3, y: 0.6)
                        )
                    )
                )
        }
        .accessibilityHidden(true)
    }
}

extension SkeletonShape where S == Capsule {
    /// Convenience for the most common skeleton element: a text-line capsule.
    static var line: SkeletonShape<Capsule> { SkeletonShape(shape: Capsule()) }
}
