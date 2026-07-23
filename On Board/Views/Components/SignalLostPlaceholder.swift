//
//  SignalLostPlaceholder.swift
//  On Board
//
//  Image-loading placeholder styled like a broadcast "no signal" test pattern:
//  a stack of bars whose shades drift until the real image arrives. It pairs
//  with the app's ephemeral, broadcast-flavored brand (the weekly wipe, "you
//  had to be there") far better than a generic gray shimmer.
//
//  Palette: monochrome by default; pass `tint` (e.g. a post's tone colour) and
//  the bars become shades of that single hue instead — never a garish rainbow,
//  which would fight the app's restrained palette.
//
//  Motion: the shade drift is driven by `TimelineView(.animation)`, NOT a
//  `repeatForever` animation — the latter keeps the app permanently non-idle
//  and makes XCUITest gesture/assertion timing flaky (see the welcome-screen
//  breathing regression). With Reduce Motion the timeline is paused: the bars
//  render as a still test pattern.
//

import SwiftUI

struct SignalLostPlaceholder: View {
    /// nil → monochrome (shades of `.primary`); otherwise shades of this hue.
    var tint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // A gentle test-pattern staircase of base opacities across the top bars…
    private let topBars: [Double] = [0.10, 0.15, 0.20, 0.27, 0.20, 0.15, 0.11]
    // …and a shorter "castellation" strip along the bottom, like the real thing.
    private let bottomBars: [Double] = [0.24, 0.09, 0.17, 0.09, 0.20]

    private var base: Color { tint ?? .primary }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.85

            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(topBars.indices, id: \.self) { i in
                        base.opacity(drift(topBars[i], index: i, phase: phase))
                    }
                }
                HStack(spacing: 3) {
                    ForEach(bottomBars.indices, id: \.self) { i in
                        base.opacity(drift(bottomBars[i], index: i + 4, phase: phase + 1.6))
                    }
                }
                .frame(height: 16)
            }
            .padding(3)
        }
        .background(base.opacity(0.05))
        .accessibilityHidden(true)
    }

    /// Oscillate a bar's opacity a touch, phase-offset per bar, so a soft wave
    /// of shade drifts across the pattern until the image replaces it.
    private func drift(_ resting: Double, index: Int, phase: Double) -> Double {
        let wave = sin(phase + Double(index) * 0.8) * 0.06
        return min(0.34, max(0.04, resting + wave))
    }
}

#Preview("Monochrome") {
    SignalLostPlaceholder()
        .frame(width: 220, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
}

#Preview("Tinted") {
    SignalLostPlaceholder(tint: .blue)
        .frame(width: 220, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
}
