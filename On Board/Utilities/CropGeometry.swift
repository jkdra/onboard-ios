//
//  PostCropGeometry.swift
//  On Board
//
//  Pure geometry for PostImageCropView's freeform/aspect-constrained crop
//  rectangle. No SwiftUI/UIKit dependency beyond CoreGraphics types, so it's
//  fully unit-testable without rendering anything.
//

import UIKit

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

nonisolated enum CropGeometry {
    // MARK: - Safe Area & Sizing

    /// Shrinks the view by the safe area and standard toolbar heights (44pt top, 49pt bottom).
    static func containerSize(for geometrySize: CGSize, safeAreaInsets: UIEdgeInsets) -> CGSize {
        let padding: CGFloat = 16
        let topInset = safeAreaInsets.top + 44
        let bottomInset = safeAreaInsets.bottom + 49
        
        let availableWidth = geometrySize.width - (padding * 2) - safeAreaInsets.left - safeAreaInsets.right
        let availableHeight = geometrySize.height - (padding * 2) - topInset - bottomInset
        
        return CGSize(
            width: availableWidth,
            height: availableHeight
        )
    }

    // MARK: - Rubber Banding Math

    static func rubberBandedScale(raw: CGFloat, min: CGFloat, max: CGFloat, friction: CGFloat = 0.3) -> CGFloat {
        if raw < min {
            return min - (min - raw) * friction
        } else if raw > max {
            return max + (raw - max) * friction
        } else {
            return raw
        }
    }

    static func rubberBandedOffset(raw: CGSize, clamped: CGSize, friction: CGFloat = 0.3) -> CGSize {
        let dx = raw.width - clamped.width
        let dy = raw.height - clamped.height
        
        return CGSize(
            width: clamped.width + dx * friction,
            height: clamped.height + dy * friction
        )
    }

    // MARK: - Frame & Ratio Math

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

        if let aspect, aspect > 0 {
            // `floor` is the minimum allowed *shorter* side. Raising width
            // and height independently would distort non-square locked
            // ratios (for example 4:5 would incorrectly become 1:1).
            let minimumWidth = aspect >= 1 ? floor * aspect : floor
            let minimumHeight = aspect >= 1 ? floor : floor / aspect
            if width < minimumWidth || height < minimumHeight {
                width = minimumWidth
                height = minimumHeight
            }
        } else {
            width = max(width, floor)
            height = max(height, floor)
        }

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
    /// fixed, clamped to `bounds` and to a minimum height/width of `minDimension`.
    /// If an `aspect` ratio is provided, the perpendicular dimension expands or
    /// contracts symmetrically around its center to preserve the ratio.
    static func resizeEdge(_ edge: CropEdge, of start: CGRect, to point: CGPoint, aspect: CGFloat? = nil, bounds: CGRect, minDimension: CGFloat = minCropDimension) -> CGRect {
        let floor = effectiveFloor(minDimension, in: bounds)
        var rect = start
        
        if let aspect, aspect > 0 {
            let minimumWidth = aspect >= 1 ? floor * aspect : floor
            let minimumHeight = aspect >= 1 ? floor : floor / aspect
            
            switch edge {
            case .top, .bottom:
                let fixedCenter = start.midX
                let maxHalfWidth = min(fixedCenter - bounds.minX, bounds.maxX - fixedCenter)
                let maxHeight = maxHalfWidth * 2 / aspect
                
                var newHeight: CGFloat
                var newY: CGFloat
                if edge == .top {
                    let maxAllowedPointY = start.maxY - minimumHeight
                    let minAllowedPointY = max(bounds.minY, start.maxY - maxHeight)
                    let newMinY = min(max(point.y, minAllowedPointY), maxAllowedPointY)
                    newHeight = start.maxY - newMinY
                    newY = newMinY
                } else {
                    let minAllowedPointY = start.minY + minimumHeight
                    let maxAllowedPointY = min(bounds.maxY, start.minY + maxHeight)
                    let newMaxY = max(min(point.y, minAllowedPointY), maxAllowedPointY)
                    newHeight = newMaxY - start.minY
                    newY = start.minY
                }
                
                let newWidth = newHeight * aspect
                rect = CGRect(x: fixedCenter - newWidth / 2, y: newY, width: newWidth, height: newHeight)
                
            case .left, .right:
                let fixedCenter = start.midY
                let maxHalfHeight = min(fixedCenter - bounds.minY, bounds.maxY - fixedCenter)
                let maxWidth = maxHalfHeight * 2 * aspect
                
                var newWidth: CGFloat
                var newX: CGFloat
                if edge == .left {
                    let maxAllowedPointX = start.maxX - minimumWidth
                    let minAllowedPointX = max(bounds.minX, start.maxX - maxWidth)
                    let newMinX = min(max(point.x, minAllowedPointX), maxAllowedPointX)
                    newWidth = start.maxX - newMinX
                    newX = newMinX
                } else {
                    let minAllowedPointX = start.minX + minimumWidth
                    let maxAllowedPointX = min(bounds.maxX, start.minX + maxWidth)
                    let newMaxX = max(min(point.x, minAllowedPointX), maxAllowedPointX)
                    newWidth = newMaxX - start.minX
                    newX = start.minX
                }
                
                let newHeight = newWidth / aspect
                rect = CGRect(x: newX, y: fixedCenter - newHeight / 2, width: newWidth, height: newHeight)
            }
        } else {
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

    // MARK: - Zoom / pan transform model
    //
    // The image is drawn at a fixed `base` fit-frame, then transformed on
    // screen by a uniform `scale` (about the base's center) and a `offset`
    // pan. The crop frame is a separate on-screen rect. The invariant is that
    // the transformed image always fully covers the crop frame — no blank
    // area inside the selection — which the clamp helpers below enforce.

    /// Where the image actually lands on screen after `scale`/`offset` are
    /// applied to the fit-`base` frame. (scaleEffect scales about the center.)
    static func effectiveImageRect(base: CGRect, scale: CGFloat, offset: CGSize) -> CGRect {
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        let center = CGPoint(x: base.midX + offset.width, y: base.midY + offset.height)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The normalized (0…1) region of the image currently inside `cropRect`,
    /// given where the image is drawn (`imageRect`). This is the source of
    /// truth for what gets cropped — independent of any screen transform.
    static func normalizedCrop(cropRect: CGRect, imageRect: CGRect) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let visibleCrop = cropRect.intersection(imageRect)
        guard !visibleCrop.isNull, !visibleCrop.isEmpty else {
            return .zero
        }
        return CGRect(
            x: (visibleCrop.minX - imageRect.minX) / imageRect.width,
            y: (visibleCrop.minY - imageRect.minY) / imageRect.height,
            width: visibleCrop.width / imageRect.width,
            height: visibleCrop.height / imageRect.height
        )
    }

    /// Source-pixel rect from a normalized (0…1) crop region.
    static func pixelRect(normalizedCrop norm: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: norm.minX * imageSize.width,
            y: norm.minY * imageSize.height,
            width: norm.width * imageSize.width,
            height: norm.height * imageSize.height
        )
    }

    /// The smallest `scale` at which the image can still cover `cropRect`
    /// (below this, even perfectly centered, the image is too small).
    static func minScaleToCover(base: CGRect, cropRect: CGRect) -> CGFloat {
        guard base.width > 0, base.height > 0 else { return 1 }
        return max(cropRect.width / base.width, cropRect.height / base.height)
    }

    /// Clamps `offset` so the transformed image still fully covers `cropRect`
    /// at the given `scale` — the image can't be panned far enough to reveal
    /// a blank edge inside the crop frame.
    static func clampOffsetToCover(offset: CGSize, base: CGRect, scale: CGFloat, cropRect: CGRect) -> CGSize {
        var o = offset
        let halfW = base.width * scale / 2
        // image.minX <= crop.minX  and  image.maxX >= crop.maxX
        let maxOX = cropRect.minX - base.midX + halfW
        let minOX = cropRect.maxX - base.midX - halfW
        o.width = minOX <= maxOX ? min(max(o.width, minOX), maxOX) : (minOX + maxOX) / 2
        let halfH = base.height * scale / 2
        let maxOY = cropRect.minY - base.midY + halfH
        let minOY = cropRect.maxY - base.midY - halfH
        o.height = minOY <= maxOY ? min(max(o.height, minOY), maxOY) : (minOY + maxOY) / 2
        return o
    }

    /// Auto-normalize: given the normalized region currently selected, produce
    /// the canonical layout — a crop frame centered and enlarged to fill
    /// `viewport` (at the selection's aspect), plus the image `scale`/`offset`
    /// that map the *same* normalized region exactly onto that frame. This is
    /// what recenters + zooms after the user settles, keeping the selected
    /// content identical while making it bigger and centered.
    static func normalizedLayout(
        normalizedCrop norm: CGRect,
        base: CGRect,
        viewport: CGRect
    ) -> (cropRect: CGRect, scale: CGFloat, offset: CGSize) {
        guard norm.width > 0, norm.height > 0, base.width > 0, base.height > 0 else {
            return (viewport, 1, .zero)
        }
        // Display aspect (w/h) of the selected region.
        let aspect = (norm.width * base.width) / (norm.height * base.height)
        let target = maxRect(forAspect: aspect, in: viewport)

        // Effective image rect that maps `norm` onto `target`.
        let imgW = target.width / norm.width
        let imgH = target.height / norm.height
        let scale = imgW / base.width
        let imgMinX = target.minX - norm.minX * imgW
        let imgMinY = target.minY - norm.minY * imgH
        let offset = CGSize(
            width: imgMinX + imgW / 2 - base.midX,
            height: imgMinY + imgH / 2 - base.midY
        )
        return (target, scale, offset)
    }
}
