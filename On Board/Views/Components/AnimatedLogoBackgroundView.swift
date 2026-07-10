//
//  AnimatedLogoBackgroundView.swift
//  On Board
//

import SwiftUI

struct AnimatedLogoBackgroundView: View {
    var color: Color = .primary
    var opacity: Double = 0.1
    var logoSize: CGFloat = 64
    var spacing: CGFloat = 40
    var angle: Angle = .degrees(-15)
    var isActive: Bool = true
    var speed: Double = 15

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    // The staggered grid repeats every `stepX` horizontally and every `2 * stepY`
    // vertically (odd rows are offset by half a step). So a single tile of that
    // size, containing the two logos needed to complete one repeat, is enough to
    // reproduce the whole infinite pattern via a hardware-tiled fill — replacing
    // what used to be ~200-300 individual `draw()` calls per frame with one.
    @State private var tile: Image?

    private var stepX: Double { Double(logoSize + spacing) }
    private var stepY: Double { Double(logoSize + spacing) }

    var body: some View {
        // 30fps is plenty for a slow diagonal drift — halves the recurring
        // per-frame cost with no perceptible difference at this speed.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isActive)) { tl in
            Canvas { ctx, size in
                guard let tile else { return }

                let t = tl.date.timeIntervalSinceReferenceDate

                // Animate diagonally
                let xOffset = reduceMotion ? 0 : -(t * speed).truncatingRemainder(dividingBy: stepX)
                let yOffset = reduceMotion ? 0 : -(t * speed).truncatingRemainder(dividingBy: stepY * 2)

                drawTiledPattern(context: ctx, size: size, tile: tile, xOffset: xOffset, yOffset: yOffset)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeIn(duration: 0.5), value: isActive)
        .task(id: TileKey(color: color, opacity: opacity, logoSize: logoSize, spacing: spacing, scale: displayScale)) {
            let key = TileKey(color: color, opacity: opacity, logoSize: logoSize, spacing: spacing, scale: displayScale)
            tile = await Self.renderTile(key: key, stepX: stepX, stepY: stepY)
        }
    }

    private func drawTiledPattern(context: GraphicsContext, size: CGSize, tile: Image, xOffset: Double, yOffset: Double) {
        // Expand the fill area to account for rotation, same as the old per-tile draw.
        let diagonal = Double(hypot(size.width, size.height))
        let drawingSize = diagonal * 1.5

        let cx = Double(size.width) / 2
        let cy = Double(size.height) / 2

        var patternCtx = context
        patternCtx.transform = patternCtx.transform
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(angle.radians)))
            .concatenating(CGAffineTransform(translationX: cx, y: cy))

        let rect = CGRect(x: -drawingSize / 2, y: -drawingSize / 2, width: drawingSize, height: drawingSize)
        patternCtx.fill(
            Path(rect),
            with: .tiledImage(tile, origin: CGPoint(x: xOffset, y: yOffset))
        )
    }

    private struct TileKey: Equatable {
        let color: Color
        let opacity: Double
        let logoSize: CGFloat
        let spacing: CGFloat
        let scale: CGFloat
    }

    @MainActor
    private static func renderTile(key: TileKey, stepX: Double, stepY: Double) async -> Image? {
        let content = ZStack(alignment: .topLeading) {
            logo(key: key).offset(x: 0, y: 0)
            logo(key: key).offset(x: key.logoSize + key.spacing / 2, y: stepY)
        }
        .frame(width: stepX, height: stepY * 2, alignment: .topLeading)

        let renderer = ImageRenderer(content: content)
        renderer.scale = key.scale
        renderer.isOpaque = false
        guard let cgImage = renderer.cgImage else { return nil }

        return Image(decorative: cgImage, scale: key.scale)
    }

    @ViewBuilder
    private static func logo(key: TileKey) -> some View {
        Image("OBLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: key.logoSize, height: key.logoSize)
            .foregroundStyle(key.color)
            .opacity(key.opacity)
    }
}

#Preview {
    AnimatedLogoBackgroundView(opacity: 0.1)
        .background(Color(.systemBackground))
}
