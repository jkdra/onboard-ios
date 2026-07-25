//
//  HostSpeechBubble.swift
//  On Board
//
//  The Host's speech bubble — a liquid-glass "game dialogue" balloon with a
//  tapered tail pointing back toward the Host beside it. The Host mascot shows
//  up at several moments (the welcome celebration, report confirmations, empty
//  states, …), so the bubble chrome lives here as one reusable piece rather
//  than inline in any single screen.
//
//  Compose it beside a Host sprite. The tail defaults to the LEADING edge, so
//  put the Host on the left:
//
//      HStack(alignment: .center, spacing: 4) {
//          Image("HostIdle").resizable().scaledToFit().frame(height: 88)
//          HostSpeechBubble { Text("Thanks — we're on it.") }
//      }
//
//  Put the Host on the right by flipping the tail:
//
//      HStack(alignment: .center, spacing: 4) {
//          HostSpeechBubble(tailEdge: .trailing) { Text("All set!") }
//          Image("HostHappy").resizable().scaledToFit().frame(height: 88)
//      }
//

import SwiftUI

struct HostSpeechBubble<Content: View>: View {
    /// Which side the tail points from — toward the Host. `.leading` (default)
    /// puts the Host on the left; `.trailing` mirrors it for a right-side Host.
    var tailEdge: HorizontalEdge = .leading
    @ViewBuilder var content: Content

    var body: some View {
        let shape = SpeechBubbleShape(tailEdge: tailEdge)
        content
            // Default Host dialogue voice; an inner `.fontStyle` on the content
            // overrides it (the welcome typewriter sizes itself explicitly).
            .fontStyle(.title3)
            .fontWeight(.heavy)
            // Keep text clear of the tail on whichever side it pokes out.
            .padding(tailEdge == .leading ? .leading : .trailing, 18 + SpeechBubbleShape.tailSize)
            .padding(tailEdge == .leading ? .trailing : .leading, 18)
            .padding(.vertical, 14)
            .background {
                // Same liquid-glass material as the info card and mute button
                // (glassEffect on iOS 26, thin material below) — no shadow; the
                // glass carries its own quiet depth.
                GlassBackground(shape: shape, fallback: AnyShapeStyle(.thinMaterial))
                shape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

/// Rounded-rect bubble with a smooth, tapered tail on one horizontal edge — one
/// continuous outline so a stroke has no seam where the tail meets the body. The
/// tail curves out of the edge and narrows to a soft, rounded tip (a modern chat
/// tail), pointing back toward the Host beside it. Its base is vertically
/// centered and shrinks to fit short bubbles, so the tail never rides into a
/// corner arc or drifts off-center.
nonisolated struct SpeechBubbleShape: Shape {
    /// How far the tail pokes out, beyond the bubble body.
    static let tailSize: CGFloat = 18

    var cornerRadius: CGFloat = 20
    /// Vertical span of the tail's base on the edge.
    var tailWidth: CGFloat = 26
    /// Which edge the tail grows from.
    var tailEdge: HorizontalEdge = .leading

    func path(in rect: CGRect) -> Path {
        let leading = leadingPath(in: rect)
        guard tailEdge == .trailing else { return leading }
        // Mirror horizontally about the rect's center for a right-side tail.
        return leading.applying(
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0)
        )
    }

    /// The bubble with its tail on the LEADING (left) edge.
    private func leadingPath(in rect: CGRect) -> Path {
        let tail = Self.tailSize
        let body = CGRect(
            x: rect.minX + tail, y: rect.minY,
            width: rect.width - tail, height: rect.height
        )
        // Fixed tail height — it does NOT shrink with the bubble (a shrinking
        // tail looked pinched on the short single-line greeting). The corner
        // radius adapts instead, so the fixed-size base always fits on the
        // straight part of the edge, even at the smallest height. `half` only
        // gives way on a pathologically tiny bubble, as a safety guard.
        let half = min(tailWidth / 2, max(2, body.height / 2 - 2))
        let r = min(cornerRadius, max(2, body.height / 2 - half - 2))
        let tipY = rect.midY
        let baseBottom = CGPoint(x: body.minX, y: tipY + half)
        let baseTop = CGPoint(x: body.minX, y: tipY - half)
        let tip = CGPoint(x: rect.minX, y: tipY)

        var p = Path()
        // Top edge, left→right, then clockwise around the body to bottom-left.
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Up the left edge to the tail base, out to the tip, back to the edge.
        p.addLine(to: baseBottom)
        p.addCurve(
            to: tip,
            control1: CGPoint(x: body.minX - tail * 0.45, y: tipY + half * 0.55),
            control2: CGPoint(x: tip.x + tail * 0.18, y: tipY + half * 0.20)
        )
        p.addCurve(
            to: baseTop,
            control1: CGPoint(x: tip.x + tail * 0.18, y: tipY - half * 0.20),
            control2: CGPoint(x: body.minX - tail * 0.45, y: tipY - half * 0.55)
        )
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

#Preview("Host + bubble") {
    VStack(spacing: 40) {
        HStack(alignment: .center, spacing: 4) {
            Image("HostIdle").resizable().scaledToFit().frame(height: 88)
            HostSpeechBubble { Text("You're in!\nWelcome On Board.") }
        }
        HStack(alignment: .center, spacing: 4) {
            HostSpeechBubble(tailEdge: .trailing) { Text("Thanks — report sent.") }
            Image("HostHappy").resizable().scaledToFit().frame(height: 88)
        }
    }
    .padding()
}
