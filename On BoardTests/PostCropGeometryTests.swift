//
//  PostCropGeometryTests.swift
//  On BoardTests
//

import CoreGraphics
import Foundation
import Testing
@testable import On_Board

struct PostCropGeometryTests {

    @Test func imageDisplayFrameFitsWideImageByWidth() {
        // 2:1 image in a square container fits by width, letterboxed vertically.
        let frame = PostCropGeometry.imageDisplayFrame(
            imageSize: CGSize(width: 200, height: 100),
            in: CGSize(width: 100, height: 100)
        )
        #expect(frame.width == 100)
        #expect(frame.height == 50)
        #expect(frame.minY == 25)
    }

    @Test func imageDisplayFrameFitsTallImageByHeight() {
        let frame = PostCropGeometry.imageDisplayFrame(
            imageSize: CGSize(width: 100, height: 200),
            in: CGSize(width: 100, height: 100)
        )
        #expect(frame.height == 100)
        #expect(frame.width == 50)
        #expect(frame.minX == 25)
    }

    @Test func maxRectNilAspectReturnsFullFrame() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(PostCropGeometry.maxRect(forAspect: nil, in: frame) == frame)
    }

    @Test func maxRectSquareInWideFrameFitsByHeight() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let square = PostCropGeometry.maxRect(forAspect: 1.0, in: frame)
        #expect(square.width == 50)
        #expect(square.height == 50)
        #expect(square.midX == frame.midX)
        #expect(square.midY == frame.midY)
    }

    @Test func rectFreeformDragGrowsFromAnchor() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = PostCropGeometry.rect(
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
        let result = PostCropGeometry.rect(
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
        let result = PostCropGeometry.rect(
            anchor: CGPoint(x: 20, y: 20),
            draggedPoint: CGPoint(x: 25, y: 22),
            aspect: nil,
            bounds: bounds
        )
        #expect(result.width == PostCropGeometry.minCropDimension)
        #expect(result.height == PostCropGeometry.minCropDimension)
    }

    @Test func rectClampsToBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = PostCropGeometry.rect(
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
        let moved = PostCropGeometry.translate(rect, by: CGSize(width: 1000, height: -1000), bounds: bounds)
        #expect(moved.minX == 70)
        #expect(moved.minY == 0)
    }

    @Test func pixelRectMapsDisplaySpaceToImagePixels() {
        // Image is 400x200 (2:1), displayed at 100x50 inside a larger frame with a 25pt x-offset.
        let imageDisplayFrame = CGRect(x: 25, y: 0, width: 100, height: 50)
        let displayRect = CGRect(x: 25, y: 0, width: 50, height: 25)
        let pixelRect = PostCropGeometry.pixelRect(
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
        let result = PostCropGeometry.rect(
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
        #expect(PostCropGeometry.anchorPoint(for: .topLeft, in: rect) == CGPoint(x: 40, y: 60))
        #expect(PostCropGeometry.draggedPoint(for: .topLeft, in: rect) == CGPoint(x: 10, y: 20))
        #expect(PostCropGeometry.anchorPoint(for: .bottomRight, in: rect) == CGPoint(x: 10, y: 20))
        #expect(PostCropGeometry.draggedPoint(for: .bottomRight, in: rect) == CGPoint(x: 40, y: 60))
    }

    @Test func edgeMidpointsAreCenteredOnEachSide() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(PostCropGeometry.edgeMidpoint(for: .top, in: rect) == CGPoint(x: 25, y: 20))
        #expect(PostCropGeometry.edgeMidpoint(for: .bottom, in: rect) == CGPoint(x: 25, y: 60))
        #expect(PostCropGeometry.edgeMidpoint(for: .left, in: rect) == CGPoint(x: 10, y: 40))
        #expect(PostCropGeometry.edgeMidpoint(for: .right, in: rect) == CGPoint(x: 40, y: 40))
    }

    @Test func resizeTopEdgeMovesOriginKeepsBottomFixed() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = PostCropGeometry.resizeEdge(.top, of: start, to: CGPoint(x: 999, y: 10), bounds: bounds)
        #expect(result.minY == 10)
        #expect(result.maxY == start.maxY)
        #expect(result.minX == start.minX)
        #expect(result.width == start.width)
    }

    @Test func resizeBottomEdgeMovesHeightKeepsTopFixed() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = PostCropGeometry.resizeEdge(.bottom, of: start, to: CGPoint(x: 999, y: 150), bounds: bounds)
        #expect(result.minY == start.minY)
        #expect(result.maxY == 150)
    }

    @Test func resizeLeftEdgeKeepsRightFixed() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = PostCropGeometry.resizeEdge(.left, of: start, to: CGPoint(x: 5, y: 999), bounds: bounds)
        #expect(result.minX == 5)
        #expect(result.maxX == start.maxX)
    }

    @Test func resizeRightEdgeKeepsLeftFixed() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = PostCropGeometry.resizeEdge(.right, of: start, to: CGPoint(x: 190, y: 999), bounds: bounds)
        #expect(result.minX == start.minX)
        #expect(result.maxX == 190)
    }

    @Test func resizeEdgeEnforcesMinimumDimension() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        // Dragging top edge almost to the bottom edge — must not collapse below minCropDimension.
        let result = PostCropGeometry.resizeEdge(.top, of: start, to: CGPoint(x: 0, y: 115), bounds: bounds)
        #expect(result.height == PostCropGeometry.minCropDimension)
    }

    @Test func resizeEdgeClampsToBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let start = CGRect(x: 20, y: 40, width: 60, height: 80)
        let result = PostCropGeometry.resizeEdge(.top, of: start, to: CGPoint(x: 0, y: -500), bounds: bounds)
        #expect(result.minY == bounds.minY)
    }
}
