//
//  TiledCanvasGeometry.swift
//  On Board
//
//  Shared geometry math for a rotated, repeating Canvas-drawn background
//  (AnimatedLogoBackgroundView's logo grid, AnimatedStripesView's stripes).
//  Both oversize their drawing area to the canvas diagonal so a rotated
//  tiled pattern has no visible corner gaps, and both rotate-then-translate
//  around the canvas center — that part is identical between them and lives
//  here. The tile loop and offset/animation math differ enough (a 2D
//  staggered image grid with linear drift vs. 1D stripes with a
//  physics-based decay/acceleration offset) that they're deliberately left
//  to each view rather than folded into one shared component.
//

import SwiftUI

enum TiledCanvasGeometry {
    /// The oversized diagonal draw size needed so a rotated tiled pattern
    /// covers the full canvas with no visible corner gaps.
    static func diagonal(for size: CGSize) -> Double {
        hypot(Double(size.width), Double(size.height))
    }

    /// Rotate around the origin, then move the origin to `center` (plus any
    /// additional offset — e.g. AnimatedStripesView baking its scroll offset
    /// directly into the translation rather than the tile origin).
    static func transform(angle: Angle, center: CGPoint, extraOffset: CGPoint = .zero) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: CGFloat(angle.radians))
            .concatenating(CGAffineTransform(translationX: center.x + extraOffset.x, y: center.y + extraOffset.y))
    }
}
