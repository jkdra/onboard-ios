//
//  FireworksView.swift
//  On Board
//
//  Monochrome, theme-adaptive fireworks for the admission celebration. Ported
//  from the tuned web prototype: an arced launch that rounds over a crest, a
//  burst of gravity-drooping sparks, luminous trails, a core flash, and a
//  twinkle-fade. An abundant opening settles into a sparse ambient trickle,
//  then it STOPS.
//
//  Rendering: TimelineView(.animation) drives a Canvas. Canvas is immediate-mode
//  (no frame persistence), so the web's "fade the whole canvas" trail trick
//  isn't available — trails are instead drawn as fading gradient streaks from a
//  short per-particle position history (a comet for each shell, a short tail for
//  each spark).
//
//  Idle-safety: the simulation is finite and self-completing, and the timeline
//  PAUSES the moment nothing is left on screen — so it never leaves the app in a
//  perpetual non-idle state that would stall XCUITest (see the
//  repeatforever-breaks-uitests note). It's ink-only and adapts to the color
//  scheme (white on dark, near-black on light), so it needs no palette.
//

import SwiftUI

struct FireworksView: View {
    /// Flip to true to fire the show once.
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var engine = FireworksEngine()
    @State private var finished = false

    private var ink: Color { scheme == .dark ? .white : Color(white: 0.10) }

    var body: some View {
        TimelineView(.animation(paused: !isActive || finished)) { timeline in
            Canvas { context, size in
                engine.stepAndPrepare(active: isActive && !finished,
                                      now: timeline.date, size: size,
                                      reduceMotion: reduceMotion)
                engine.render(into: context, ink: ink)
                if engine.isComplete && !finished {
                    DispatchQueue.main.async { finished = true }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

/// Immediate-mode particle sim for `FireworksView`. Held in `@State` (a
/// reference type persists across frames); the TimelineView drives redraws, so
/// mutating it here never touches SwiftUI state.
final class FireworksEngine {

    private struct Shell {
        var x, y, vx, vy, vdrag, grav, targetY: Double
        var trail: [CGPoint] = []
    }
    private struct Spark {
        var x, y, vx, vy, grav, drag, life, ttl, size, tw, tws: Double
        var trail: [CGPoint] = []
    }
    private struct Flash { var x, y, life, ttl, max: Double }

    private var shells: [Shell] = []
    private var sparks: [Spark] = []
    private var flashes: [Flash] = []
    private var schedule: [Double] = []   // seconds-since-start at which to launch a shell

    private var started = false
    private var reduceMotion = false
    private var width = 0.0, height = 0.0
    private var startTime: Date?
    private var lastTime: Date?
    private var accumulator = 0.0

    var isComplete: Bool {
        started && schedule.isEmpty && shells.isEmpty && sparks.isEmpty && flashes.isEmpty
    }

    // MARK: Drive

    func stepAndPrepare(active: Bool, now: Date, size: CGSize, reduceMotion: Bool) {
        guard active, !isComplete else { return }
        width = Double(size.width); height = Double(size.height)
        if !started {
            begin(now: now, reduceMotion: reduceMotion)
            started = true
        }
        advance(now: now)
    }

    private func begin(now: Date, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        startTime = now
        lastTime = now
        schedule.removeAll()
        if reduceMotion {
            schedule = [0]                       // one gentle shell, no spectacle
            return
        }
        var t = 0.0
        for _ in 0..<Int.random(in: 5...7) {     // abundant opening, close together
            schedule.append(t); t += Double.random(in: 0.105...0.28)
        }
        t += Double.random(in: 0.55...1.1)       // a beat of calm
        for _ in 0..<Int.random(in: 4...7) {     // sparse ambient trickle
            schedule.append(t); t += Double.random(in: 0.95...2.35)
        }
    }

    private func advance(now: Date) {
        guard let start = startTime, let last = lastTime else { return }
        let elapsed = now.timeIntervalSince(start)
        let dt = now.timeIntervalSince(last)
        lastTime = now

        while let next = schedule.first, next <= elapsed {
            schedule.removeFirst()
            launchShell()
        }

        // Fixed 60Hz timestep so the physics matches the tuned prototype at any
        // refresh rate; cap the backlog so a stall can't spiral.
        accumulator = min(accumulator + max(0, dt), 4.0 / 60.0)
        while accumulator >= 1.0 / 60.0 {
            stepOnce()
            accumulator -= 1.0 / 60.0
        }
    }

    // MARK: Sim

    private func launchShell() {
        let dir: Double = Bool.random() ? -1 : 1
        shells.append(Shell(
            x: width * 0.5 + Double.random(in: -width * 0.08 ... width * 0.08),
            y: height * 1.02,
            vx: dir * Double.random(in: 1.3...2.0),   // lateral kick -> a rounded arc
            vy: -Double.random(in: 11.8...15.5),      // wide -> varied burst heights
            vdrag: 0.996,                             // keep horizontal alive: path curves over
            grav: 0.16,
            targetY: Double.random(in: height * 0.13 ... height * 0.36)
        ))
    }

    private func burst(x: Double, y: Double, ivx: Double, ivy: Double) {
        let n = reduceMotion ? 26 : Int.random(in: 42...58)
        let base = Double.random(in: 3.2...4.4)
        for i in 0..<n {
            let ang = Double(i) / Double(n) * (.pi * 2) + Double.random(in: -0.06...0.06)
            let spd = base * Double.random(in: 0.55...1.2)
            sparks.append(Spark(
                x: x, y: y,
                vx: cos(ang) * spd + ivx * 0.5,      // inherit the shell's arc momentum
                vy: sin(ang) * spd + ivy * 0.5,
                grav: 0.055, drag: 0.965,
                life: 0, ttl: Double.random(in: 46...86),
                size: Double.random(in: 1.3...2.7),
                tw: Double.random(in: 0 ... (.pi * 2)), tws: Double.random(in: 0.4...0.7)
            ))
        }
        flashes.append(Flash(x: x, y: y, life: 0, ttl: 15, max: Double.random(in: 30...46)))
    }

    private func stepOnce() {
        var liveShells: [Shell] = []
        for var sh in shells {
            sh.trail.append(CGPoint(x: sh.x, y: sh.y))
            if sh.trail.count > 14 { sh.trail.removeFirst() }
            sh.vy += sh.grav
            sh.vx *= sh.vdrag
            sh.x += sh.vx
            sh.y += sh.vy
            if sh.vy >= 0.5 || sh.y <= sh.targetY {   // a hair past apex: the crest rounds over
                burst(x: sh.x, y: sh.y, ivx: sh.vx, ivy: sh.vy)
            } else {
                liveShells.append(sh)
            }
        }
        shells = liveShells

        var liveSparks: [Spark] = []
        for var s in sparks {
            s.trail.append(CGPoint(x: s.x, y: s.y))
            if s.trail.count > 5 { s.trail.removeFirst() }
            s.vx *= s.drag
            s.vy *= s.drag
            s.vy += s.grav                            // gravity droop
            s.x += s.vx
            s.y += s.vy
            s.life += 1
            if s.life < s.ttl { liveSparks.append(s) }
        }
        sparks = liveSparks

        flashes = flashes.compactMap { var f = $0; f.life += 1; return f.life < f.ttl ? f : nil }
    }

    // MARK: Render

    func render(into context: GraphicsContext, ink: Color) {
        // Sparks: fading gradient streak from the tail to the (twinkling) head.
        for s in sparks {
            let a = max(0, 1 - s.life / s.ttl)
            let twinkle = 0.62 + 0.38 * abs(sin(s.life * s.tws + s.tw))
            let alpha = a * twinkle
            if alpha <= 0.02 { continue }
            let head = CGPoint(x: s.x, y: s.y)
            if let tail = s.trail.first, hypot(s.x - Double(tail.x), s.y - Double(tail.y)) > 0.6 {
                var p = Path(); p.move(to: tail); p.addLine(to: head)
                context.stroke(
                    p,
                    with: .linearGradient(
                        Gradient(colors: [ink.opacity(0), ink.opacity(alpha)]),
                        startPoint: tail, endPoint: head),
                    style: StrokeStyle(lineWidth: CGFloat(s.size), lineCap: .round))
            } else {
                context.fill(
                    Path(ellipseIn: CGRect(x: s.x - s.size / 2, y: s.y - s.size / 2, width: s.size, height: s.size)),
                    with: .color(ink.opacity(alpha)))
            }
        }

        // Burst flash: a soft expanding bloom.
        for f in flashes {
            let t = f.life / f.ttl
            let r = max(f.max * t, 1)
            let alpha = (1 - t) * 0.85
            if alpha <= 0.02 { continue }
            context.fill(
                Path(ellipseIn: CGRect(x: f.x - r, y: f.y - r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(
                    Gradient(colors: [ink.opacity(alpha), ink.opacity(0)]),
                    center: CGPoint(x: f.x, y: f.y), startRadius: 0, endRadius: r))
        }

        // Rising shells: a comet trail + a glowing head.
        for sh in shells {
            let head = CGPoint(x: sh.x, y: sh.y)
            if let tail = sh.trail.first, sh.trail.count > 1 {
                var p = Path(); p.addLines(sh.trail + [head])
                context.stroke(
                    p,
                    with: .linearGradient(
                        Gradient(colors: [ink.opacity(0), ink.opacity(0.9)]),
                        startPoint: tail, endPoint: head),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(
                    Path(ellipseIn: CGRect(x: sh.x - 2.2, y: sh.y - 2.2, width: 4.4, height: 4.4)),
                    with: .color(ink))
            }
        }
    }
}
