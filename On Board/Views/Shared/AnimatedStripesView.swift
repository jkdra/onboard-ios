//
//  AnimatedStripesView.swift
//  On Board
//
//  Physics-based stripe animation for edit-mode backgrounds.
//  Entry: decaying velocity burst settles to a slow crawl.
//  Exit: constant acceleration away in the same direction.
//

import SwiftUI

struct AnimatedStripesView: View {
    var color: Color = .primary
    var opacity: Double = 0.05
    var stripeWidth: CGFloat = 64
    var spacing: CGFloat = 64
    var angle: Angle = .degrees(15)
    var isActive: Bool

    // pt/sec — settled crawl speed while in edit mode
    private let driftSpeed: Double = 18
    // Initial velocity burst above drift at the moment of entry (pt)
    private let entryBurst: Double = 380
    // Decay constant — 3.5 ≈ 95% settled after ~0.85 s
    private let entryDecay: Double = 3.5
    // Constant exit acceleration (pt/s²) — makes stripes visibly flee
    private let exitAccel: Double = 900

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var enteredAt: Date? = nil
    @State private var exitedAt: Date? = nil
    @State private var offsetAtExit: Double = 0
    @State private var stripeOpacity: Double = 0
    @State private var cleanupTask: Task<Void, Never>? = nil

    private var step: Double { Double(stripeWidth + spacing) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || enteredAt == nil)) { tl in
            Canvas { ctx, size in
                // When motion is reduced, xOffset stays 0 — static texture only
                let xOffset = reduceMotion ? 0 : currentRawOffset(at: tl.date)
                    .truncatingRemainder(dividingBy: step)
                drawStripes(context: ctx, size: size, xOffset: xOffset)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .opacity(stripeOpacity)
        .onAppear {
            if isActive {
                enteredAt = .now
                stripeOpacity = 1
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                cleanupTask?.cancel()
                cleanupTask = nil
                offsetAtExit = 0
                exitedAt = nil
                if !reduceMotion { enteredAt = .now }
                let fadeDuration = reduceMotion ? 0.4 : 0.25
                withAnimation(.easeIn(duration: fadeDuration)) { stripeOpacity = 1 }
            } else {
                if let entered = enteredAt {
                    offsetAtExit = rawOffset(at: .now, enteredAt: entered, exitedAt: nil)
                }
                if !reduceMotion { exitedAt = .now }
                // Reduced motion: simple fade. Full motion: instant fade so it snaps away.
                let fadeDuration = reduceMotion ? 0.35 : 0.15
                withAnimation(.easeIn(duration: fadeDuration)) { stripeOpacity = 0 }
                cleanupTask = Task {
                    try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : 0.35))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        enteredAt = nil
                        exitedAt = nil
                    }
                }
            }
        }
    }

    // MARK: - Math

    private func currentRawOffset(at date: Date) -> Double {
        guard let entered = enteredAt else { return offsetAtExit }
        return rawOffset(at: date, enteredAt: entered, exitedAt: exitedAt)
    }

    private func rawOffset(at date: Date, enteredAt: Date, exitedAt: Date?) -> Double {
        let tActive = max(0, date.timeIntervalSince(enteredAt))

        // Entry / active phase — integrate decaying burst + constant drift:
        //   v(t) = drift + burst · e^(−decay · t)
        //   x(t) = drift·t + (burst/decay)·(1 − e^(−decay·t))
        let entryX = driftSpeed * tActive
            + (entryBurst / entryDecay) * (1 - exp(-entryDecay * tActive))

        guard let exitedAt else { return entryX }

        // Exit phase — constant acceleration from drift speed:
        //   v(t) = drift + accel·t  →  x(t) = drift·t + ½·accel·t²
        let tExit = max(0, date.timeIntervalSince(exitedAt))
        return offsetAtExit + driftSpeed * tExit + 0.5 * exitAccel * tExit * tExit
    }

    // MARK: - Drawing

    private func drawStripes(context: GraphicsContext, size: CGSize, xOffset: Double) {
        let diagonal = Double(hypot(size.width, size.height))
        let stripeCount = Int(diagonal / step) + 6
        let cx = Double(size.width) / 2
        let cy = Double(size.height) / 2

        let transform = CGAffineTransform(rotationAngle: CGFloat(angle.radians))
            .concatenating(CGAffineTransform(translationX: cx + xOffset, y: cy))

        let originX = -diagonal / 2 - step
        for i in 0..<stripeCount {
            let x = originX + Double(i) * step
            var path = Path()
            path.addRect(CGRect(x: x, y: -diagonal / 2, width: Double(stripeWidth), height: diagonal))
            context.fill(path.applying(transform), with: .color(color.opacity(opacity)))
        }
    }
}
