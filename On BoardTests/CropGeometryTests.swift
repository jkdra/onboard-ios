//
//  CropGeometryTests.swift
//  On BoardTests
//

import CoreGraphics
import Foundation
import Testing
@testable import On_Board

struct CropGeometryTests {

    @Test func imageDisplayFrameFitsWideImageByWidth() {
        // 2:1 image in a square container fits by width, letterboxed vertically.
        let frame = CropGeometry.imageDisplayFrame(
            imageSize: CGSize(width: 200, height: 100),
            in: CGSize(width: 100, height: 100)
        )
        #expect(frame.width == 100)
        #expect(frame.height == 50)
        #expect(frame.minY == 25)
    }

    @Test func imageDisplayFrameFitsTallImageByHeight() {
        let frame = CropGeometry.imageDisplayFrame(
            imageSize: CGSize(width: 100, height: 200),
            in: CGSize(width: 100, height: 100)
        )
        #expect(frame.height == 100)
        #expect(frame.width == 50)
        #expect(frame.minX == 25)
    }

    @Test func maxRectNilAspectReturnsFullFrame() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(CropGeometry.maxRect(forAspect: nil, in: frame) == frame)
    }

    @Test func maxRectSquareInWideFrameFitsByHeight() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let square = CropGeometry.maxRect(forAspect: 1.0, in: frame)
        #expect(square.width == 50)
        #expect(square.height == 50)
        #expect(square.midX == frame.midX)
        #expect(square.midY == frame.midY)
    }

    @Test func rectFreeformDragGrowsFromAnchor() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = CropGeometry.rect(
            anchor: CGPoint(x: 20, y: 20),
            draggedPoint: CGPoint(x: 120, y: 80),
            aspect: nil,
            bounds: bounds
        )
        #expect(result == CGRect(x: 20, y: 20, width: 100, height: 60))
    }

    @Test func rectHonorsAspectFromWidth() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        // width dominates (100 vs height 60) at aspect 1:1 -> width wins, height matches it.
        let result = CropGeometry.rect(
            anchor: CGPoint(x: 0, y: 0),
            draggedPoint: CGPoint(x: 100, y: 60),
            aspect: 1.0,
            bounds: bounds
        )
        #expect(result.width == 100)
        #expect(result.height == 100)
    }

    @Test func rectEnforcesMinimumDimension() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = CropGeometry.rect(
            anchor: CGPoint(x: 20, y: 20),
            draggedPoint: CGPoint(x: 25, y: 22),
            aspect: nil,
            bounds: bounds
        )
        #expect(result.width == CropGeometry.minCropDimension)
        #expect(result.height == CropGeometry.minCropDimension)
    }

    @Test func rectClampsToBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = CropGeometry.rect(
            anchor: CGPoint(x: 80, y: 80),
            draggedPoint: CGPoint(x: 300, y: 300),
            aspect: nil,
            bounds: bounds
        )
        #expect(result.maxX <= 100)
        #expect(result.maxY <= 100)
    }

    @Test func translateClampsInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect = CGRect(x: 10, y: 10, width: 30, height: 30)
        let moved = CropGeometry.translate(rect, by: CGSize(width: 1000, height: -1000), bounds: bounds)
        #expect(moved.minX == 70)
        #expect(moved.minY == 0)
    }

    @Test func pixelRectMapsDisplaySpaceToImagePixels() {
        // Image is 400x200 (2:1), displayed at 100x50 inside a larger frame with a 25pt x-offset.
        let imageDisplayFrame = CGRect(x: 25, y: 0, width: 100, height: 50)
        let displayRect = CGRect(x: 25, y: 0, width: 50, height: 25)
        let pixelRect = CropGeometry.pixelRect(
            from: displayRect,
            imageDisplayFrame: imageDisplayFrame,
            imageSize: CGSize(width: 400, height: 200)
        )
        #expect(pixelRect == CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func rectPreservesAspectWhenAspectAdjustmentOverflowsBounds() {
        // Tall, narrow bounds. Aspect 0.2 (narrow) combined with a drag point
        // that pushes the naive aspect-adjusted height (450) well past
        // bounds.height (300), while width (90) stays under bounds.width (100).
        // Without a proportional shrink, `clamp` would clip height down to 300
        // independently and leave width at 90, breaking the requested aspect
        // (90/300 = 0.3 != 0.2).
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 300)
        let result = CropGeometry.rect(
            anchor: CGPoint(x: 0, y: 0),
            draggedPoint: CGPoint(x: 90, y: 250),
            aspect: 0.2,
            bounds: bounds
        )
        #expect(abs(result.width / result.height - 0.2) < 0.001)
        #expect(result.width <= bounds.width)
        #expect(result.height <= bounds.height)
    }

    @Test func anchorAndDraggedPointAreOppositeCorners() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(CropGeometry.anchorPoint(for: .topLeft, in: rect) == CGPoint(x: 40, y: 60))
        #expect(CropGeometry.draggedPoint(for: .topLeft, in: rect) == CGPoint(x: 10, y: 20))
        #expect(CropGeometry.anchorPoint(for: .bottomRight, in: rect) == CGPoint(x: 10, y: 20))
        #expect(CropGeometry.draggedPoint(for: .bottomRight, in: rect) == CGPoint(x: 40, y: 60))
    }

    @Test func edgeMidpointsAreCenteredOnEachSide() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(CropGeometry.edgeMidpoint(for: .top, in: rect) == CGPoint(x: 25, y: 20))
        #expect(CropGeometry.edgeMidpoint(for: .bottom, in: rect) == CGPoint(x: 25, y: 60))
        #expect(CropGeometry.edgeMidpoint(for: .left, in: rect) == CGPoint(x: 10, y: 40))
        #expect(CropGeometry.edgeMidpoint(for: .right, in: rect) == CGPoint(x: 40, y: 40))
    }

    @Test func resizeTopEdgeMovesOriginKeepsBottomFixed() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = CropGeometry.resizeEdge(.top, of: start, to: CGPoint(x: 999, y: 10), bounds: bounds)
        #expect(result.minY == 10)
        #expect(result.maxY == start.maxY)
        #expect(result.minX == start.minX)
        #expect(result.width == start.width)
    }

    @Test func resizeBottomEdgeMovesHeightKeepsTopFixed() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = CropGeometry.resizeEdge(.bottom, of: start, to: CGPoint(x: 999, y: 150), bounds: bounds)
        #expect(result.minY == start.minY)
        #expect(result.maxY == 150)
    }

    @Test func resizeLeftEdgeKeepsRightFixed() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = CropGeometry.resizeEdge(.left, of: start, to: CGPoint(x: 5, y: 999), bounds: bounds)
        #expect(result.minX == 5)
        #expect(result.maxX == start.maxX)
    }

    @Test func resizeRightEdgeKeepsLeftFixed() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = CropGeometry.resizeEdge(.right, of: start, to: CGPoint(x: 190, y: 999), bounds: bounds)
        #expect(result.minX == start.minX)
        #expect(result.maxX == 190)
    }

    @Test func resizeEdgeEnforcesMinimumDimension() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        // Dragging top edge almost to the bottom edge — must not collapse below minCropDimension.
        let result = CropGeometry.resizeEdge(.top, of: start, to: CGPoint(x: 0, y: 115), bounds: bounds)
        #expect(result.height == CropGeometry.minCropDimension)
    }

    @Test func resizeEdgeClampsToBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = CropGeometry.resizeEdge(.top, of: start, to: CGPoint(x: 0, y: -500), bounds: bounds)
        #expect(result.minY == bounds.minY)
    }

    @Test func rectHonorsRaisedMinimumDimension() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        // Tiny drag that would normally collapse to minCropDimension (60),
        // but a raised floor of 150 must win.
        let result = CropGeometry.rect(
            anchor: CGPoint(x: 20, y: 20),
            draggedPoint: CGPoint(x: 25, y: 25),
            aspect: nil,
            bounds: bounds,
            minDimension: 150
        )
        #expect(result.width == 150)
        #expect(result.height == 150)
    }

    @Test func resizeEdgeHonorsRaisedMinimumDimension() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let start = CGRect(x: 20, y: 20, width: 300, height: 300)
        // Drag bottom edge almost up to the top — a 150 floor caps the collapse.
        let result = CropGeometry.resizeEdge(.bottom, of: start, to: CGPoint(x: 0, y: 25), bounds: bounds, minDimension: 150)
        #expect(result.height == 150)
    }

    @Test func effectiveFloorNeverExceedsBounds() {
        // A resolution-derived floor larger than the image must clamp down to
        // the bounds, never force a rect bigger than what's available.
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        #expect(CropGeometry.effectiveFloor(500, in: bounds) == 80)
        // And it never drops below the baseline minimum.
        #expect(CropGeometry.effectiveFloor(10, in: bounds) == CropGeometry.minCropDimension)
    }

    @Test func normalizedCropClampsSelectionToImageBounds() {
        let normalized = CropGeometry.normalizedCrop(
            cropRect: CGRect(x: -20, y: 10, width: 80, height: 80),
            imageRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        #expect(normalized == CGRect(x: 0, y: 0.1, width: 0.6, height: 0.8))
    }

    @Test func effectiveImageRectAppliesScaleAroundCenterAndOffset() {
        let imageRect = CropGeometry.effectiveImageRect(
            base: CGRect(x: 50, y: 100, width: 200, height: 100),
            scale: 2,
            offset: CGSize(width: 30, height: -20)
        )

        #expect(imageRect == CGRect(x: -20, y: 30, width: 400, height: 200))
    }

    @Test func clampOffsetKeepsCropCoveredByTransformedImage() {
        let base = CGRect(x: 0, y: 0, width: 200, height: 100)
        let crop = CGRect(x: 50, y: 25, width: 100, height: 50)
        let offset = CropGeometry.clampOffsetToCover(
            offset: CGSize(width: 500, height: -500),
            base: base,
            scale: 1,
            cropRect: crop
        )
        let imageRect = CropGeometry.effectiveImageRect(base: base, scale: 1, offset: offset)

        #expect(imageRect.minX <= crop.minX)
        #expect(imageRect.maxX >= crop.maxX)
        #expect(imageRect.minY <= crop.minY)
        #expect(imageRect.maxY >= crop.maxY)
        #expect(offset == CGSize(width: 50, height: -25))
    }

    @Test func normalizedLayoutPreservesTheSelectedSourceRegion() {
        let base = CGRect(x: 20, y: 40, width: 200, height: 100)
        let viewport = CGRect(x: 20, y: 40, width: 200, height: 100)
        let source = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.5)
        let layout = CropGeometry.normalizedLayout(
            normalizedCrop: source,
            base: base,
            viewport: viewport
        )
        let imageRect = CropGeometry.effectiveImageRect(
            base: base,
            scale: layout.scale,
            offset: layout.offset
        )
        let actual = CropGeometry.normalizedCrop(cropRect: layout.cropRect, imageRect: imageRect)

        #expect(abs(actual.minX - source.minX) < 0.001)
        #expect(abs(actual.minY - source.minY) < 0.001)
        #expect(abs(actual.width - source.width) < 0.001)
        #expect(abs(actual.height - source.height) < 0.001)
        #expect(layout.cropRect.midX == viewport.midX)
        #expect(layout.cropRect.midY == viewport.midY)
    }

    @Test func rectPreservesLockedAspectWhileEnforcingMinimumShortSide() {
        let result = CropGeometry.rect(
            anchor: .zero,
            draggedPoint: CGPoint(x: 2, y: 2),
            aspect: 4.0 / 5.0,
            bounds: CGRect(x: 0, y: 0, width: 400, height: 400),
            minDimension: 100
        )

        #expect(result.width == 100)
        #expect(result.height == 125)
        #expect(abs(result.width / result.height - (4.0 / 5.0)) < 0.001)
    }
}
