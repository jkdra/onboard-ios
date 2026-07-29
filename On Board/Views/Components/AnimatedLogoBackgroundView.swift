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

    private var stepX: Double { Double(logoSize + spacing) }
    private var stepY: Double { Double(logoSize + spacing) }

    var body: some View {
        // 30fps is plenty for a slow diagonal drift
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isActive)) { tl in
            Canvas { ctx, size in
                let image = ctx.resolve(Image("OBLogo").renderingMode(.template))
                
                let t = tl.date.timeIntervalSinceReferenceDate
                
                // Animate diagonally
                let xOffset = reduceMotion ? 0 : -(t * speed).truncatingRemainder(dividingBy: stepX * 2)
                let yOffset = reduceMotion ? 0 : -(t * speed).truncatingRemainder(dividingBy: stepY * 2)
                
                drawLogos(context: ctx, size: size, image: image, xOffset: xOffset, yOffset: yOffset)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeIn(duration: 0.5), value: isActive)
    }

    private func drawLogos(context: GraphicsContext, size: CGSize, image: GraphicsContext.ResolvedImage, xOffset: Double, yOffset: Double) {
        // Expand the drawing area to account for rotation
        let diagonal = TiledCanvasGeometry.diagonal(for: size)
        let drawingSize = diagonal * 1.5

        let countX = Int(drawingSize / stepX) + 4
        let countY = Int(drawingSize / stepY) + 4

        let cx = Double(size.width) / 2
        let cy = Double(size.height) / 2

        let transform = TiledCanvasGeometry.transform(angle: angle, center: CGPoint(x: cx, y: cy))

        let originX = -drawingSize / 2 + xOffset
        let originY = -drawingSize / 2 + yOffset
        
        var imageCtx = context
        imageCtx.transform = imageCtx.transform.concatenating(transform)
        imageCtx.addFilter(.colorMultiply(color))
        imageCtx.opacity = opacity
        
        for i in 0..<countX {
            for j in 0..<countY {
                // Stagger rows
                let offsetX = originX + Double(i) * stepX + (j % 2 != 0 ? stepX / 2 : 0)
                let offsetY = originY + Double(j) * stepY
                
                let rect = CGRect(
                    x: offsetX,
                    y: offsetY,
                    width: Double(logoSize),
                    height: Double(logoSize)
                )
                
                imageCtx.draw(image, in: rect)
            }
        }
    }
}

#Preview {
    AnimatedLogoBackgroundView(opacity: 0.1)
        .background(Color(.systemBackground))
}
