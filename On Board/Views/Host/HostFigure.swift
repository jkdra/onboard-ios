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

enum HostBodyState: String, CaseIterable {
    case idle, speech

    var art: HostPathData {
        switch self {
        case .idle: HostArt.bodyIdle
        case .speech: HostArt.bodySpeech
        }
    }
}

enum HostEye: String, CaseIterable {
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

enum HostArticle: String, CaseIterable {
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
    var eyeCenter = CGPoint(x: 0.28, y: 0.25)
    var eyeScale: CGFloat = 0.22
    var sweatCenter = CGPoint(x: 0.02, y: 0.14)
    var sweatScale: CGFloat = 0.24
    var angerCenter = CGPoint(x: 0.84, y: 0.16)
    var angerScale: CGFloat = 0.26

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
    var weight: CGFloat = 0.08
    /// World-space (screen) axis extension, as fractions of body width.
    /// Default leans down-right like the drawn asset.
    var axis: CGVector = CGVector(dx: 0.045, dy: 0.085)
    /// Knockout halo around articles, as a fraction of body width.
    var halo: CGFloat = 0.05

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

    var body: some View {
        GeometryReader { proxy in
            let art = body_.art
            let scale = min(proxy.size.width / art.width, proxy.size.height / art.height)
            let bodySize = CGSize(width: art.width * scale, height: art.height * scale)
            let box = CGRect(
                x: (proxy.size.width - bodySize.width) / 2,
                y: (proxy.size.height - bodySize.height) / 2,
                width: bodySize.width,
                height: bodySize.height
            )
            let w = box.width
            let strokeWidth = weight * w * 2
            let bodyPath = art.path(in: box)

            ZStack {
                // Axis extension (behind), then contour — same color, so
                // their union reads as one asymmetric outline.
                silhouette(bodyPath, stroke: strokeWidth)
                    .offset(x: axisInLocal.dx * w, y: axisInLocal.dy * w)
                silhouette(bodyPath, stroke: strokeWidth)

                bodyPath.fill(bodyColor)

                component(eye.art, center: anatomy.eyeCenter, scale: anatomy.eyeScale, in: box)
                    .foregroundStyle(lineColor)

                if let article {
                    let haloWidth = halo * w * 2
                    // Halo knocks out EVERYTHING beneath within the
                    // figure's compositing group — contour, shadow, body —
                    // erasing to transparency.
                    articleView(article, in: box, strokeWidth: haloWidth, color: .black)
                        .blendMode(.destinationOut)
                    articleView(article, in: box, strokeWidth: 0, color: lineColor)
                }
            }
            .compositingGroup()
            .rotationEffect(pose)
        }
        .aspectRatio(body_.art.width / body_.art.height, contentMode: .fit)
    }

    /// The body silhouette dilated by `stroke/2`: filled + stroked.
    private func silhouette(_ path: Path, stroke: CGFloat) -> some View {
        path
            .strokedPath(StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            .union(path)
            .fill(lineColor)
    }

    @ViewBuilder
    private func component(_ art: HostPathData, center: CGPoint, scale: CGFloat, in box: CGRect) -> some View {
        let width = scale * box.width
        let height = width * art.height / art.width
        HostGlyph(art: art)
            .frame(width: width, height: height)
            .position(
                x: box.minX + center.x * box.width,
                y: box.minY + center.y * box.height
            )
    }

    @ViewBuilder
    private func articleView(_ article: HostArticle, in box: CGRect, strokeWidth: CGFloat, color: Color) -> some View {
        let art = article.art
        let width = anatomy.scale(for: article) * box.width
        let height = width * art.height / art.width
        let frame = CGRect(
            x: box.minX + anatomy.center(for: article).x * box.width - width / 2,
            y: box.minY + anatomy.center(for: article).y * box.height - height / 2,
            width: width,
            height: height
        )
        let path = art.path(in: frame)
        if strokeWidth > 0 {
            path
                .strokedPath(StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                .union(path)
                .fill(color)
        } else {
            path.fill(color)
        }
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
