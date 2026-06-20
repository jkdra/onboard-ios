//
//  StripesOverlay.swift
//  On Board
//
//  Diagonal-band texture used as an "editing / creating" backdrop in
//  the post detail edit mode and the new-post composer.
//

import SwiftUI

struct StripesOverlay: View {
    var color: Color = .primary
    var opacity: Double = 0.05
    var stripeWidth: CGFloat = 64
    var spacing: CGFloat = 64
    var angle: Angle = .degrees(15)

    var body: some View {
        
        HStack (spacing: spacing){
            ForEach(0..<6) { _ in
                Rectangle()
                    .fill(color.opacity(opacity))
                    .frame(minWidth: stripeWidth, minHeight: 1060)
                    .rotationEffect(angle)
            }
        }
        .ignoresSafeArea()
//        Canvas { context, size in
//            let step = stripeWidth + spacing
//            // The diagonal is the longest distance across any rectangle, so a
//            // stripe field sized to it fully covers the canvas at any rotation
//            // and any aspect ratio (iPhone portrait, iPad landscape, etc.).
//            let diagonal = hypot(size.width, size.height)
//            let stripeCount = Int(diagonal / step) + 4
//            let center = CGPoint(x: size.width / 2, y: size.height / 2)
//
//            // Rotate each stripe around the canvas center instead of rotating
//            // the whole view. This keeps the geometry inside the Canvas frame
//            // so corners don't get clipped by the parent.
//            let transform = CGAffineTransform(rotationAngle: CGFloat(angle.radians))
//                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
//
//            let originX = -diagonal / 2
//
//            for index in 0..<stripeCount {
//                let x = originX + CGFloat(index) * step
//                var path = Path()
//                path.addRect(CGRect(
//                    x: x,
//                    y: -diagonal / 2,
//                    width: stripeWidth,
//                    height: diagonal
//                ))
//                context.fill(
//                    path.applying(transform),
//                    with: .color(color.opacity(opacity)),
//                    style: FillStyle()
//                )
//            }
//        }
//        .allowsHitTesting(false)
//        .ignoresSafeArea()
    }
}

#Preview {
    StripesOverlay(color: .blue, opacity: 0.15)
        .background(Color.blue.opacity(0.1))
}
