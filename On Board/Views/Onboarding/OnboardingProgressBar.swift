//
//  OnboardingProgressBar.swift
//  On Board
//
//  Monochrome fill with a one-shot prismatic glint: a rapid shimmer sweeps
//  leading → trailing across the filled region as the fill grows — on appear
//  and on step advance — then parks clear. Progress feedback, not ambient
//  motion (same parked-off-range gesture as GlassFieldChrome's focus flash).
//  Every step view creates its own instance (no shared state — see CLAUDE.md
//  on the removed namespace).
//

import SwiftUI

struct OnboardingProgressBar: View {
    @Environment(\.glassEffectsEnabled) private var glassEffectsEnabled
    let step: Int
    var totalSteps: Int = 4
    /// Preview-only: shows a button that replays the fill + sweep on demand.
    var debug: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shimmerPhase: CGFloat = 0
    @State private var fill: CGFloat = 0

    private let shimmerW: CGFloat = 0.32
    private let shimmerDuration: Double = 1.0
    private let growDuration: Double = 0.7

    /// Spectral stops in dispersion order — a hint of refracted color as the
    /// glint passes, not a colored bar. The fill itself stays monochrome.
    private let glintColors: [Color] = [
        .clear,
        Color(.systemRed).opacity(0.9),
        Color(.systemYellow).opacity(0.95),
        Color(.systemTeal).opacity(0.95),
        .white,
        .clear,
    ]

    private var target: CGFloat {
        min(1, CGFloat(step) / CGFloat(totalSteps))
    }

    /// Sweeps the FULL unit space: phase 0 parks the gradient entirely before
    /// x=0 (last stop `.clear` covers everything visible) and phase 1 entirely
    /// past x=1 (first stop `.clear` covers it). The previous
    /// `(fill + 2W) * phase` scaling stopped the sweep at the fill edge, which
    /// left the teal stops parked *visibly inside* the fill on early steps —
    /// masked by the old repeatForever loop, exposed by a one-shot sweep.
    private var shimmerCenter: CGFloat {
        (-shimmerW) + (1 + shimmerW * 2) * shimmerPhase
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                trackBackground

                // Filled track with shimmer overlay
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color.primary)

                    LinearGradient(
                        colors: glintColors,
                        startPoint: UnitPoint(x: shimmerCenter - shimmerW, y: 0.5),
                        endPoint: UnitPoint(x: shimmerCenter + shimmerW, y: 0.5)
                    )
                }
                .mask {
                    Capsule(style: .continuous)
                        .frame(width: max(0, proxy.size.width * fill))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(alignment: .bottom) {
                    if debug {
                        Button {
                            withAnimation(.smooth(duration: growDuration)) { fill = target }
                            sweepShimmer()
                        } label: {
                            Label("Test Sweep", systemImage: "checkmark")
                        }
                    }
                }
            }
        }
        .frame(height: 6)
        .onAppear {
            if reduceMotion {
                fill = target
                return
            }
            withAnimation(.smooth(duration: 0.8)) { fill = target }
            sweepShimmer()
        }
        .onChange(of: step) { _, _ in
            if reduceMotion {
                fill = target
                return
            }
            withAnimation(.smooth(duration: growDuration)) { fill = target }
            sweepShimmer()
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step) of \(totalSteps)")
    }

    @ViewBuilder
    private var trackBackground: some View {
        if #available(iOS 26.0, *), glassEffectsEnabled {
            Color.clear
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
                )
        } else {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.12))
        }
    }

    /// One rapid leading → trailing sweep across the filled region, then the
    /// gradient parks clear (phase 0 and 1 both place it fully off the fill).
    /// The Task-based pause (NOT Animation.delay — a delayed animation started
    /// during the navigation push freezes mid-sweep) lets the glint ride the
    /// fill-growth animation.
    private func sweepShimmer() {
        shimmerPhase = 0
        Task {
            // Let the fill start growing so the glint rides it, not leads it.
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: shimmerDuration)) {
                shimmerPhase = 1
            }
        }
    }
}

#Preview {
    OnboardingProgressBar(step: 4, debug: true)
        .padding()
}
