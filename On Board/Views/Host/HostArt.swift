import SwiftUI

// The Host's vector anatomy, extracted from the Illustrator source PDFs
// (Downloads/{Body,Eyes,Articles}, 2026-08-07) via a CGPDFScanner script.
// Assets are authored UPRIGHT; the rig (HostFigure) applies the pose angle.
// Each component is a tight-cropped glyph on its own canvas — positioning
// is computed by HostAnatomy, not baked into the art.
//
// Coordinates are PDF-space (y-up); `HostPathData` flips to SwiftUI space
// (y-down) when building the Path.

/// A single vector glyph: canvas size plus a compact op string
/// ("M x y", "L x y", "C x1 y1 x2 y2 x y", "R x y w h", "Z").
nonisolated struct HostPathData {
    let width: CGFloat
    let height: CGFloat
    private let ops: [Op]

    enum Op {
        case move(CGPoint)
        case line(CGPoint)
        case curve(CGPoint, CGPoint, CGPoint)
        case rect(CGRect)
        case close
    }

    init(width: CGFloat, height: CGFloat, data: String) {
        self.width = width
        self.height = height
        var parsed: [Op] = []
        let tokens = data.split(separator: " ")
        var i = 0
        func num(_ offset: Int) -> CGFloat {
            CGFloat(Double(tokens[i + offset]) ?? 0)
        }
        while i < tokens.count {
            switch tokens[i] {
            case "M": parsed.append(.move(CGPoint(x: num(1), y: num(2)))); i += 3
            case "L": parsed.append(.line(CGPoint(x: num(1), y: num(2)))); i += 3
            case "C":
                parsed.append(.curve(
                    CGPoint(x: num(1), y: num(2)),
                    CGPoint(x: num(3), y: num(4)),
                    CGPoint(x: num(5), y: num(6))
                ))
                i += 7
            case "R":
                parsed.append(.rect(CGRect(x: num(1), y: num(2), width: num(3), height: num(4))))
                i += 5
            case "Z": parsed.append(.close); i += 1
            default: i += 1
            }
        }
        self.ops = parsed
    }

    /// Builds the glyph scaled into `rect` (aspect is the CALLER's job —
    /// pass a rect with this data's aspect ratio). Flips PDF y-up to
    /// SwiftUI y-down.
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / width
        let sy = rect.height / height
        func pt(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + p.x * sx, y: rect.minY + (height - p.y) * sy)
        }
        var path = Path()
        for op in ops {
            switch op {
            case .move(let p): path.move(to: pt(p))
            case .line(let p): path.addLine(to: pt(p))
            case .curve(let c1, let c2, let p):
                path.addCurve(to: pt(p), control1: pt(c1), control2: pt(c2))
            case .rect(let r):
                let flipped = CGRect(
                    x: rect.minX + r.minX * sx,
                    y: rect.minY + (height - r.maxY) * sy,
                    width: r.width * sx,
                    height: r.height * sy
                )
                path.addRect(flipped)
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// SwiftUI Shape wrapper: aspect-fits the glyph into whatever rect the
/// layout provides, centered.
// nonisolated: this module defaults to MainActor isolation, and a
// MainActor-isolated Shape conformance is rejected — path(in:) must be
// callable off-main (same idiom as CacheEnvelope's hand-written Codable).
nonisolated struct HostGlyph: Shape {
    let art: HostPathData

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / art.width, rect.height / art.height)
        let size = CGSize(width: art.width * scale, height: art.height * scale)
        let fitted = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        return art.path(in: fitted)
    }
}

// nonisolated: pure data, and the test target reads these statics from a
// nonisolated context (module isolation defaults to MainActor).
nonisolated enum HostArt {
    // MARK: Body (white interior silhouette; contour + shadow are computed)
    static let bodyIdle = HostPathData(width: 3513.21, height: 4267.07, data: "M 3513.21 1247.01 L 3513.21 614.48 C 3513.21 275.34 3237.87 0.00 2898.73 0.00 L 614.48 0.00 C 275.34 0.00 0.00 275.34 0.00 614.48 L 0.00 3652.59 C 0.00 3991.73 275.34 4267.07 614.48 4267.07 L 2898.73 4267.07 C 3237.87 4267.07 3513.21 3991.73 3513.21 3652.59 L 3513.21 2912.21 L 2948.43 2079.61 Z")
    static let bodySpeech = HostPathData(width: 3513.15, height: 4267.00, data: "M 3513.15 1805.45 L 3513.15 614.47 C 3513.15 275.33 3237.82 0.00 2898.68 0.00 L 614.47 0.00 C 275.33 0.00 0.00 275.33 0.00 614.47 L 0.00 3652.53 C 0.00 3991.67 275.33 4267.00 614.47 4267.00 L 2898.68 4267.00 C 3237.82 4267.00 3513.15 3991.67 3513.15 3652.53 L 3513.15 2356.58 L 2948.38 2079.58 Z")

    // MARK: Eyes
    static let eyeNeutral = HostPathData(width: 4267.00, height: 4267.00, data: "M 2133.50 4267.00 C 3311.01 4267.00 4267.00 3311.01 4267.00 2133.50 C 4267.00 955.99 3311.01 0.00 2133.50 0.00 C 955.99 0.00 0.00 955.99 0.00 2133.50 C 0.00 3311.01 955.99 4267.00 2133.50 4267.00 Z")
    static let eyeHappy = HostPathData(width: 4267.00, height: 4267.00, data: "M 4267.00 2133.50 L 3200.25 2133.50 C 3200.25 2722.65 2722.65 3200.25 2133.50 3200.25 C 1544.35 3200.25 1066.75 2722.65 1066.75 2133.50 L 0.00 2133.50 C -0.00 3311.80 955.20 4267.00 2133.50 4267.00 C 3311.80 4267.00 4267.00 3311.80 4267.00 2133.50 Z")
    static let eyeSad = HostPathData(width: 4267.00, height: 4267.00, data: "M 4148.93 2682.84 L 645.83 660.33 L 112.46 1584.16 L 3615.56 3606.67 Z")
    static let eyeAngry = HostPathData(width: 4267.00, height: 4267.00, data: "M 3615.56 660.33 L 112.46 2682.84 L 645.83 3606.67 L 4148.93 1584.16 Z")
    static let eyeLove = HostPathData(width: 4267.00, height: 4267.00, data: "M 2133.49 3297.64 C 2543.48 4039.36 3363.45 4039.36 3773.44 3668.50 C 4183.44 3297.64 4183.44 2555.93 3773.44 1814.22 C 3486.44 1257.93 2748.47 701.65 2133.49 330.79 C 1518.52 701.65 780.55 1257.93 493.56 1814.22 C 83.57 2555.93 83.57 3297.64 493.56 3668.50 C 903.54 4039.36 1723.51 4039.36 2133.49 3297.64 Z")
    static let eyeDead = HostPathData(width: 4267.00, height: 4267.00, data: "M 3241.11 227.64 L 224.84 3243.91 L 1020.28 4039.36 L 4036.55 1023.09 Z M 4036.55 3243.91 L 1020.28 227.64 L 224.84 1023.09 L 3241.11 4039.36 Z")
    static let eyeBugged = HostPathData(width: 4267.00, height: 4267.00, data: "R 108.18 1600.13 4045.03 1066.75")

    // MARK: Emotion articles
    static let articleSweat = HostPathData(width: 4267.00, height: 4267.00, data: "M 2133.50 4267.00 C 2133.50 4267.00 3307.57 2101.95 3307.57 1174.07 C 3307.57 526.08 2781.49 0.00 2133.50 0.00 C 1485.51 0.00 959.43 526.08 959.43 1174.07 C 959.43 2101.95 2133.50 4267.00 2133.50 4267.00 Z")
    static let articleAnger = HostPathData(width: 4267.00, height: 4267.00, data: "M 1639.19 160.05 L 1962.85 1220.92 C 2093.66 1649.70 2534.12 1903.99 2970.86 1802.89 L 4051.43 1552.76 L 3924.21 1003.19 L 2843.64 1253.32 C 2695.79 1287.55 2546.68 1201.46 2502.40 1056.31 L 2178.74 -4.56 Z M 638.48 3523.22 L 1395.39 2712.49 C 1701.31 2384.81 1701.31 1876.22 1395.39 1548.54 L 638.48 737.81 L 226.15 1122.77 L 983.05 1933.50 C 1086.62 2044.43 1086.62 2216.60 983.05 2327.53 L 226.15 3138.27 Z M 3649.43 3194.24 L 3924.21 3257.85 L 4051.43 2708.28 L 3776.64 2644.67 L 2970.86 2458.14 C 2534.12 2357.04 2093.66 2611.34 1962.85 3040.11 L 1721.49 3831.21 L 1639.19 4100.98 L 2178.74 4265.60 L 2261.04 3995.82 L 2502.40 3204.73 C 2546.68 3059.57 2695.79 2973.48 2843.64 3007.71 Z")
}
