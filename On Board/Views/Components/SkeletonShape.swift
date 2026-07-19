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

import SwiftUI

struct SkeletonShape<S: Shape>: View {
    var shape: S

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: CGFloat = -0.4

    private var highlight: Color {
        scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.05)
    }

    var body: some View {
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
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
            .accessibilityHidden(true)
    }
}

extension SkeletonShape where S == Capsule {
    /// Convenience for the most common skeleton element: a text-line capsule.
    static var line: SkeletonShape<Capsule> { SkeletonShape(shape: Capsule()) }
}
