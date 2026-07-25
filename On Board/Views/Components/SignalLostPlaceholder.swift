//
//  SignalLostPlaceholder.swift
//  On Board
//
//  Image-loading placeholder styled like a broadcast "no signal" test pattern:
//  three rows of bars that glow up and then hard-cut back to dark, like a signal
//  building and dropping out. It pairs with the app's ephemeral, broadcast-
//  flavored brand (the weekly wipe, "you had to be there") far better than a
//  generic gray shimmer.
//
//  Layout: the tall colour bars fill the top two-thirds; the bottom third is a
//  short fine "castellation" strip plus a thicker block row (~2.3× the strip).
//  Monochrome by default; pass `tint` (e.g. a post's tone colour) and the bars
//  become shades of that single hue — never a garish rainbow.
//
//  Motion: each bar follows a sawtooth in time — it eases UP (pastel → vibrant)
//  then snaps DOWN instantly (the "all the way down" is a hard cut, the gradual
//  part animates). Driven by `TimelineView(.animation)`, NOT a `repeatForever`
//  animation (which keeps the app non-idle and makes XCUITest timing flaky). It
//  keeps animating under Reduce Motion on purpose: a shade cross-fade with no
//  positional movement isn't the motion that setting suppresses.
//

import SwiftUI

struct SignalLostPlaceholder: View {
    /// nil → monochrome (shades of `.primary`); otherwise shades of this hue.
    var tint: Color? = nil

    private let topCount = 7
    private let midCount = 11
    private let botCount = 5

    private let minOpacity = 0.13
    private let maxOpacity = 0.55
    /// Sawtooth cycles per second (how often a bar builds + cuts).
    private let cycleSpeed = 0.55

    private var base: Color { tint ?? .primary }

    var body: some View {
        GeometryReader { geo in
            // The two bottom rows together take up the bottom third; the short
            // fine strip is ~0.3 of that, the block row ~0.7 (≈2.3× the strip).
            let bottomThird = geo.size.height / 3
            let midHeight = bottomThird * 0.3
            let botHeight = bottomThird * 0.7

            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate

                VStack(spacing: 3) {
                    // Tall bars fill the remaining top two-thirds — build travels L→R.
                    row(count: topCount, time: time, leftToRight: true)

                    // Short fine strip — build travels R→L.
                    row(count: midCount, time: time, leftToRight: false)
                        .frame(height: midHeight)

                    // Thicker block row — build travels L→R.
                    row(count: botCount, time: time, leftToRight: true)
                        .frame(height: botHeight)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .background(base.opacity(0.05))
        .accessibilityHidden(true)
    }

    private func row(count: Int, time: Double, leftToRight: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                base.opacity(shade(bar: i, of: count, time: time, leftToRight: leftToRight))
            }
        }
    }

    /// Sawtooth per bar: eases UP to a per-bar peak, then snaps instantly back to
    /// dark. Each bar has a distinct peak and a phase offset, so at any instant
    /// the bars read as a varied test pattern and the hard cuts sweep across the
    /// row (direction set by `leftToRight`).
    private func shade(bar i: Int, of count: Int, time: Double, leftToRight: Bool) -> Double {
        let dir = leftToRight ? 1.0 : -1.0
        // Distinct phase per bar → the build/cut travels across the row.
        let phase = time * cycleSpeed * dir + Double(i) * 0.28
        let saw = phase - floor(phase)                       // 0 → 1 rise, then instant reset

        // Ease the rise (slow-in) so the build glides and the drop stays a snap.
        let eased = saw * saw

        // Distinct per-bar peak so the bars differ like real test-pattern bars.
        let peak = 0.55 + 0.45 * sin(Double(i) * 1.7)        // 0.10 … 1.0
        let v = eased * peak                                 // 0 … peak

        return minOpacity + v * (maxOpacity - minOpacity)
    }
}

#Preview("Monochrome") {
    SignalLostPlaceholder()
        .frame(width: 240, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
}

#Preview("Tinted") {
    SignalLostPlaceholder(tint: .blue)
        .frame(width: 240, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
}
