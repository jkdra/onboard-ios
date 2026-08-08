import SwiftUI

// The Host, assembled from components (HostArt) with a COMPUTED
// outline-shadow. The drawn brand asset's asymmetric outline is really two
// operations, reproduced here parametrically so it adapts to any pose:
//
//   1. CONTOUR — a uniform dilation of the body silhouette: the body path
//      stroked with 2·weight and filled.
//   2. AXIS EXTENSION — the same dilated silhouette translated along a
//      world-space vector (screen-down-ish) and unioned behind. Both copies
//      paint the same color, so the union is free. The visible margin in
//      any direction n is weight + max(0, axis·n): minimum `weight`
//      everywhere, growing on the side facing the axis — the "cast weight"
//      of the drawn original.
//
// Because the axis is WORLD-space, it is counter-rotated into body-local
// space (`axisInLocal`) before the pose rotation is applied — as the Host
// tumbles, the weight continuously pours toward whichever edge faces
// screen-down. Both the rotation and the counter-rotated offset derive
// from the same `pose`, so they animate in lockstep.
//
// Emotion articles ride with the body and knock out everything beneath
// their halo (`.destinationOut` inside the figure's compositing group) —
// the sticker-on-sticker separation from the source art, erasing to
// TRANSPARENCY so it works over any background.

nonisolated enum HostBodyState: String, CaseIterable {
    case idle, speech

    var art: HostPathData {
        switch self {
        case .idle: HostArt.bodyIdle
        case .speech: HostArt.bodySpeech
        }
    }
}

nonisolated enum HostEye: String, CaseIterable {
    case neutral, happy, sad, angry, love, dead, bugged

    var art: HostPathData {
        switch self {
        case .neutral: HostArt.eyeNeutral
        case .happy: HostArt.eyeHappy
        case .sad: HostArt.eyeSad
        case .angry: HostArt.eyeAngry
        case .love: HostArt.eyeLove
        case .dead: HostArt.eyeDead
        case .bugged: HostArt.eyeBugged
        }
    }
}

nonisolated enum HostArticle: String, CaseIterable {
    case sweat, anger

    var art: HostPathData {
        switch self {
        case .sweat: HostArt.articleSweat
        case .anger: HostArt.articleAnger
        }
    }
}

/// Placement of the movable components, in fractions of the body's box
/// (x right, y down from the body's top-leading corner; scale is width
/// relative to body width). One place to tune; the lab exposes sliders.
struct HostAnatomy {
    // Defaults tuned by Jawad in the lab, 2026-08-07.
    var eyeCenter = CGPoint(x: 0.260, y: 0.215)
    var eyeScale: CGFloat = 0.315
    var sweatCenter = CGPoint(x: -0.083, y: 0.142)
    var sweatScale: CGFloat = 0.444
    var angerCenter = CGPoint(x: 0.000, y: 0.006)
    var angerScale: CGFloat = 0.332

    func center(for article: HostArticle) -> CGPoint {
        switch article {
        case .sweat: sweatCenter
        case .anger: angerCenter
        }
    }

    func scale(for article: HostArticle) -> CGFloat {
        switch article {
        case .sweat: sweatScale
        case .anger: angerScale
        }
    }
}

struct HostFigure: View {
    var body_: HostBodyState = .idle
    var eye: HostEye = .neutral
    var article: HostArticle? = nil

    /// Pose rotation. The brand's default stance is −8° (leaning left).
    var pose: Angle = .degrees(-8)
    /// Uniform contour thickness, as a fraction of body width.
    /// Defaults tuned by Jawad in the lab, 2026-08-07.
    var weight: CGFloat = 0.093
    /// World-space (screen) axis extension, as fractions of body width.
    /// Default leans down-right like the drawn asset.
    var axis: CGVector = CGVector(dx: 0.065, dy: 0.083)
    /// Knockout halo around articles, as a fraction of body width.
    var halo: CGFloat = 0.02

    var anatomy = HostAnatomy()
    var lineColor: Color = .black
    var bodyColor: Color = .white

    /// The world-space axis expressed in body-local coordinates, so the
    /// extension stays screen-down while the body rotates.
    private var axisInLocal: CGVector {
        let t = -pose.radians
        return CGVector(
            dx: axis.dx * cos(t) - axis.dy * sin(t),
            dy: axis.dx * sin(t) + axis.dy * cos(t)
        )
    }

    // RENDERING (rebuilt for cost, 2026-08-07). One `Canvas`, ~4 fills per
    // frame, zero per-frame stroke computation:
    //   - The dilated silhouette (body stroked + filled — the expensive
    //     stroke-geometry tessellation) is pose-INDEPENDENT, so it's
    //     memoized per (body, size, weight) in HostSilhouetteMemo. The
    //     previous Shape-tree version recomputed `strokedPath` 24× per
    //     animation frame.
    //   - The sweep appends 24 translated copies of the memoized path into
    //     ONE Path filled ONCE (nonzero winding unions the overlap), so the
    //     GPU shades each shadow pixel once instead of blending ~48 layers.
    //   - The article knockout uses GraphicsContext's native
    //     `.destinationOut` inside the canvas's own transparent layer — no
    //     compositingGroup over a view tree.
    //   - `rotationEffect` stays OUTSIDE the canvas: the pose spin is a
    //     pure Core Animation transform (render-server work); the canvas
    //     content only changes because the world-fixed axis counter-rotates.
    var body: some View {
        GeometryReader { proxy in
            let art = body_.art
            let scale = min(proxy.size.width / art.width, proxy.size.height / art.height)
            let bodySize = CGSize(width: art.width * scale, height: art.height * scale)
            // The canvas is oversized: contour and shadow overflow the body
            // box, and Canvas clips to its bounds (Shape views didn't).
            let pad = bodySize.width * 0.35
            let axisLocal = axisInLocal

            Canvas { context, _ in
                let box = CGRect(x: pad, y: pad, width: bodySize.width, height: bodySize.height)
                let w = box.width
                let dilated = HostSilhouetteMemo.dilated(
                    for: body_, size: bodySize, weight: weight
                ).offsetBy(dx: pad, dy: pad)

                // 24 translated fills of the SAME cached path — deliberately
                // NOT appended into one path: the stroked outline is a ring
                // whose inner contour winds opposite its outer, so merged
                // copies cancel each other's winding where they overlap and
                // punch sliver holes in the shadow. Same-color overdraw of
                // separate fills has no winding interaction.
                for step in 0..<Self.sweepSteps {
                    let t = CGFloat(step) / CGFloat(Self.sweepSteps - 1)
                    var copy = context
                    copy.translateBy(x: axisLocal.dx * w * t, y: axisLocal.dy * w * t)
                    copy.fill(dilated, with: .color(lineColor))
                }
                context.fill(art.path(in: box), with: .color(bodyColor))
                context.fill(
                    componentPath(eye.art, center: anatomy.eyeCenter, scale: anatomy.eyeScale, in: box),
                    with: .color(lineColor)
                )

                if let article {
                    let path = articlePath(article, in: box)
                    let haloStyle = Self.contourStyle(width: halo * w * 2)
                    context.blendMode = .destinationOut
                    context.fill(path.strokedPath(haloStyle), with: .color(.black))
                    context.fill(path, with: .color(.black))
                    context.blendMode = .normal
                    context.fill(path, with: .color(lineColor))
                }
            }
            .frame(width: bodySize.width + pad * 2, height: bodySize.height + pad * 2)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .rotationEffect(pose)
        }
        .aspectRatio(body_.art.width / body_.art.height, contentMode: .fit)
    }

    /// How many interpolated copies the shadow sweep paints (t = 0 is the
    /// contour itself). 24 puts adjacent copies well under a point apart at
    /// display sizes — 8 left visible scalloping on diagonal edges under
    /// zoom. They land in one fill of one path; this is not a hot cost.
    private static var sweepSteps: Int { 24 }

    /// Miter joins, not round: the contour's corners must read POINTED,
    /// matching the drawn asset (round joins visibly soften the mouth
    /// wedge and the body corners).
    nonisolated static func contourStyle(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }

    private func componentPath(_ art: HostPathData, center: CGPoint, scale: CGFloat, in box: CGRect) -> Path {
        let width = scale * box.width
        let height = width * art.height / art.width
        return art.path(in: CGRect(
            x: box.minX + center.x * box.width - width / 2,
            y: box.minY + center.y * box.height - height / 2,
            width: width,
            height: height
        ))
    }

    private func articlePath(_ article: HostArticle, in box: CGRect) -> Path {
        componentPath(
            article.art,
            center: anatomy.center(for: article),
            scale: anatomy.scale(for: article),
            in: box
        )
    }
}

/// Memo for the dilated body silhouette (stroke tessellation is the only
/// expensive geometry in the figure, and it's pose-independent). Keyed on
/// body state + quantized size + weight; entries are few (one per distinct
/// figure size on screen) and small.
nonisolated enum HostSilhouetteMemo {
    private struct Key: Hashable {
        let body: HostBodyState
        let w: Int   // size quantized to 1/4 pt
        let h: Int
        let weight: Int  // quantized to 0.0001
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var store: [Key: Path] = [:]

    static func dilated(for body: HostBodyState, size: CGSize, weight: CGFloat) -> Path {
        let key = Key(
            body: body,
            w: Int(size.width * 4), h: Int(size.height * 4),
            weight: Int(weight * 10_000)
        )
        lock.lock()
        defer { lock.unlock() }
        if let cached = store[key] { return cached }
        let path = body.art.path(in: CGRect(origin: .zero, size: size))
        var dilated = path.strokedPath(
            HostFigure.contourStyle(width: weight * size.width * 2)
        )
        dilated.addPath(path)
        store[key] = dilated
        return dilated
    }
}

#Preview("Default 8°") {
    HostFigure()
        .frame(width: 220)
        .padding(60)
}

#Preview("Stressed, speaking") {
    HostFigure(body_: .speech, eye: .bugged, article: .sweat)
        .frame(width: 220)
        .padding(60)
}
