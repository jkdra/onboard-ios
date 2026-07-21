//
//  PostCropGeometry.swift
//  On Board
//
//  Pure geometry for PostImageCropView's freeform/aspect-constrained crop
//  rectangle. No SwiftUI/UIKit dependency beyond CoreGraphics types, so it's
//  fully unit-testable without rendering anything.
//

import CoreGraphics

nonisolated enum CropCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// A single edge of the crop rect, for independent width/height resizing.
/// Freeform only — dragging one edge while an aspect ratio is locked would
/// have to also move a perpendicular edge to preserve the ratio, which isn't
/// what a single-edge handle is for.
nonisolated enum CropEdge: CaseIterable {
    case top, bottom, left, right
}

nonisolated enum PostCropGeometry {
    /// Smallest allowed crop-rect side, in points, on either axis.
    static let minCropDimension: CGFloat = 60

    /// Where `imageSize` lands inside `containerSize` under `.scaledToFit()`.
    static func imageDisplayFrame(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        let displaySize: CGSize
        if imageAspect > containerAspect {
            displaySize = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            displaySize = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }
        let origin = CGPoint(
            x: (containerSize.width - displaySize.width) / 2,
            y: (containerSize.height - displaySize.height) / 2
        )
        return CGRect(origin: origin, size: displaySize)
    }

    /// The largest rect of `aspect` (width / height) centered within `frame`.
    /// `aspect == nil` (freeform) returns `frame` itself, uncropped.
    static func maxRect(forAspect aspect: CGFloat?, in frame: CGRect) -> CGRect {
        guard let aspect, aspect > 0 else { return frame }
        let frameAspect = frame.width / frame.height
        let size: CGSize
        if aspect > frameAspect {
            size = CGSize(width: frame.width, height: frame.width / aspect)
        } else {
            size = CGSize(width: frame.height * aspect, height: frame.height)
        }
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The corner point that stays fixed while `corner` is being dragged.
    static func anchorPoint(for corner: CropCorner, in rect: CGRect) -> CGPoint {
        draggedPoint(for: opposite(of: corner), in: rect)
    }

    /// The point of `rect` that a given corner's drag handle sits on.
    static func draggedPoint(for corner: CropCorner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private static func opposite(of corner: CropCorner) -> CropCorner {
        switch corner {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomLeft: return .topRight
        case .bottomRight: return .topLeft
        }
    }

    /// Builds a rect from a fixed `anchor` corner and the live `draggedPoint`
    /// of the opposite corner, honoring `aspect` (nil = free), a minimum
    /// size, and `bounds` clamping. `minDimension` lets the caller raise the
    /// floor above `minCropDimension` — e.g. to enforce a minimum output
    /// resolution — but it's clamped to the bounds so a large floor can never
    /// make the rect exceed the image.
    static func rect(anchor: CGPoint, draggedPoint: CGPoint, aspect: CGFloat?, bounds: CGRect, minDimension: CGFloat = minCropDimension) -> CGRect {
        let floor = effectiveFloor(minDimension, in: bounds)
        var point = draggedPoint
        point.x = min(max(point.x, bounds.minX), bounds.maxX)
        point.y = min(max(point.y, bounds.minY), bounds.maxY)

        var width = abs(point.x - anchor.x)
        var height = abs(point.y - anchor.y)

        if let aspect, aspect > 0 {
            if width / aspect >= height {
                height = width / aspect
            } else {
                width = height * aspect
            }
        }

        width = max(width, floor)
        height = max(height, floor)

        if width > bounds.width || height > bounds.height {
            let scale = min(bounds.width / width, bounds.height / height)
            width = max(width * scale, floor)
            height = max(height * scale, floor)
        }

        let originX = point.x >= anchor.x ? anchor.x : anchor.x - width
        let originY = point.y >= anchor.y ? anchor.y : anchor.y - height

        return clamp(CGRect(x: originX, y: originY, width: width, height: height), to: bounds)
    }

    /// Clamps a requested minimum crop dimension so it can never exceed the
    /// bounds it must fit inside (a resolution-derived floor on a small image
    /// would otherwise force a rect larger than the image).
    static func effectiveFloor(_ requested: CGFloat, in bounds: CGRect) -> CGFloat {
        min(max(requested, minCropDimension), min(bounds.width, bounds.height))
    }

    /// The midpoint of a given edge of `rect` — where an edge-drag handle sits.
    static func edgeMidpoint(for edge: CropEdge, in rect: CGRect) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    /// Moves a single edge of `start` to `point`, keeping the opposite edge
    /// and both perpendicular bounds fixed, clamped to `bounds` and to a
    /// minimum height/width of `minDimension` (defaults to `minCropDimension`).
    static func resizeEdge(_ edge: CropEdge, of start: CGRect, to point: CGPoint, bounds: CGRect, minDimension: CGFloat = minCropDimension) -> CGRect {
        let floor = effectiveFloor(minDimension, in: bounds)
        var rect = start
        switch edge {
        case .top:
            let newMinY = min(max(point.y, bounds.minY), start.maxY - floor)
            rect.origin.y = newMinY
            rect.size.height = start.maxY - newMinY
        case .bottom:
            let newMaxY = max(min(point.y, bounds.maxY), start.minY + floor)
            rect.size.height = newMaxY - start.minY
        case .left:
            let newMinX = min(max(point.x, bounds.minX), start.maxX - floor)
            rect.origin.x = newMinX
            rect.size.width = start.maxX - newMinX
        case .right:
            let newMaxX = max(min(point.x, bounds.maxX), start.minX + floor)
            rect.size.width = newMaxX - start.minX
        }
        return rect
    }

    /// Moves `rect` by `translation`, clamped so it stays fully inside `bounds`.
    static func translate(_ rect: CGRect, by translation: CGSize, bounds: CGRect) -> CGRect {
        var r = rect
        r.origin.x += translation.width
        r.origin.y += translation.height
        return clamp(r, to: bounds)
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }

    /// Maps a crop rect from on-screen display coordinates into the source
    /// image's pixel coordinates, given where the image was displayed.
    static func pixelRect(from displayRect: CGRect, imageDisplayFrame: CGRect, imageSize: CGSize) -> CGRect {
        guard imageDisplayFrame.width > 0 else { return .zero }
        let scale = imageSize.width / imageDisplayFrame.width
        return CGRect(
            x: (displayRect.minX - imageDisplayFrame.minX) * scale,
            y: (displayRect.minY - imageDisplayFrame.minY) * scale,
            width: displayRect.width * scale,
            height: displayRect.height * scale
        )
    }
}
