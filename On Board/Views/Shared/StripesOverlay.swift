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
        Canvas { context, size in
            let step = stripeWidth + spacing
            // Diagonal covers the canvas at any rotation and aspect ratio.
            let diagonal = hypot(size.width, size.height)
            let stripeCount = Int(diagonal / step) + 4
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            let transform = CGAffineTransform(rotationAngle: CGFloat(angle.radians))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))

            let originX = -diagonal / 2

            for index in 0..<stripeCount {
                let x = originX + CGFloat(index) * step
                var path = Path()
                path.addRect(CGRect(x: x, y: -diagonal / 2, width: stripeWidth, height: diagonal))
                context.fill(path.applying(transform), with: .color(color.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

#Preview {
    StripesOverlay(color: .blue, opacity: 0.15)
        .background(Color.blue.opacity(0.1))
}
