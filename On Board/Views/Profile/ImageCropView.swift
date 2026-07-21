//
//  ImageCropView.swift
//  On Board
//
//  Circular photo crop tool. Pure SwiftUI — pinch (MagnifyGesture) and pan
//  (DragGesture) drive .scaleEffect()/.offset() directly, no UIKit bridging.
//

import SwiftUI
import UIKit

struct ImageCropView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyDelta: CGFloat = 1.0

    @State private var offset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero

    private let padding: CGFloat = 16
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5
    // Reference "distance" for scale's rubber-band curve — scale is a multiplier,
    // not a screen dimension, so this just sets how far past minScale/maxScale it
    // can stretch before resistance gets very strong (see rubberBanded(_:range:dimension:)).
    private let scaleElasticity: CGFloat = 0.4
    // Settle-back after an over-drag/over-pinch. `.smooth` is a *fully damped* spring
    // (no overshoot) — this matches UIScrollView's native rubber-band, which decelerates
    // to the boundary and stops clean. A springy `.spring(dampingFraction: 0.75)` instead
    // overshoots the edge and wobbles, which is the "toy-like / not native" tell.
    private let settleAnimation: Animation = .smooth(duration: 0.3)

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // Clamped to 0: during the crop sheet's presentation transition,
                // geometry.size briefly reports a width smaller than the padding,
                // which would otherwise go negative and produce invalid-frame
                // warnings on every view sized from maskSize below.
                let maskSize = max(0, min(geometry.size.width - (padding * 2), 600))
                let imageAspect = image.size.width / image.size.height
                // Sized so the image's shorter dimension exactly fills the crop
                // circle at scale == 1 — the image is never smaller than the
                // visible crop area, so there's no "blank corners" case to guard.
                let baseWidth = imageAspect > 1 ? maskSize * imageAspect : maskSize
                let baseHeight = imageAspect > 1 ? maskSize : maskSize / imageAspect

                // Elastic during the gesture (rubber-banded past the limit, like
                // UIScrollView's native bounce) — hard-clamped only once the gesture
                // ends, via the spring animation in each .onEnded below.
                let liveScale = rubberBanded(scale * magnifyDelta, range: minScale...maxScale, dimension: scaleElasticity)
                let liveOffset = CGSize(
                    width: rubberBanded(
                        offset.width + dragDelta.width,
                        range: panRange(scale: liveScale, dimension: baseWidth, maskSize: maskSize),
                        dimension: maskSize
                    ),
                    height: rubberBanded(
                        offset.height + dragDelta.height,
                        range: panRange(scale: liveScale, dimension: baseHeight, maskSize: maskSize),
                        dimension: maskSize
                    )
                )

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: baseWidth, height: baseHeight)
                        .scaleEffect(liveScale)
                        .offset(liveOffset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .gesture(
                            SimultaneousGesture(
                                MagnifyGesture()
                                    .updating($magnifyDelta) { value, state, _ in
                                        state = value.magnification
                                    }
                                    .onEnded { value in
                                        // Freeze the exact rubber-banded value already on screen into
                                        // `scale` first, with NO animation — @GestureState resets
                                        // magnifyDelta to 1.0 the instant the gesture ends, which is
                                        // itself unanimated. If the spring below started from the OLD
                                        // committed `scale` instead, that instant reset plus the
                                        // not-yet-progressed animation would combine into a one-frame
                                        // flash back to the pre-gesture position before springing
                                        // forward to the clamped one. Freezing first means there's
                                        // nothing to visually jump — the animation's starting point
                                        // already matches what's on screen.
                                        scale = rubberBanded(scale * value.magnification, range: minScale...maxScale, dimension: scaleElasticity)
                                        withAnimation(settleAnimation) {
                                            scale = scale.clamped(to: minScale...maxScale)
                                            clampOffset(maskSize: maskSize, baseWidth: baseWidth, baseHeight: baseHeight)
                                        }
                                    },
                                DragGesture()
                                    .updating($dragDelta) { value, state, _ in
                                        state = value.translation
                                    }
                                    .onEnded { value in
                                        // Same reasoning as the magnify gesture above.
                                        offset = CGSize(
                                            width: rubberBanded(
                                                offset.width + value.translation.width,
                                                range: panRange(scale: scale, dimension: baseWidth, maskSize: maskSize),
                                                dimension: maskSize
                                            ),
                                            height: rubberBanded(
                                                offset.height + value.translation.height,
                                                range: panRange(scale: scale, dimension: baseHeight, maskSize: maskSize),
                                                dimension: maskSize
                                            )
                                        )
                                        withAnimation(settleAnimation) {
                                            clampOffset(maskSize: maskSize, baseWidth: baseWidth, baseHeight: baseHeight)
                                        }
                                    }
                            )
                        )
                        // Composed with drag/magnify already on this view — a plain
                        // .onTapGesture(count: 2) would lose gesture arbitration here
                        // and silently never fire.
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    if scale > minScale {
                                        scale = minScale
                                        offset = .zero
                                    } else {
                                        scale = min(doubleTapScale, maxScale)
                                        clampOffset(maskSize: maskSize, baseWidth: baseWidth, baseHeight: baseHeight)
                                    }
                                }
                            }
                        )

                    // The mask overlay
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 3000, height: 3000)
                        .reverseMask {
                            Circle()
                                .frame(width: maskSize, height: maskSize)
                        }
                        .allowsHitTesting(false)

                    // The circle guide with gridlines
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)

                        // Vertical gridlines
                        Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1).offset(x: -maskSize / 6)
                        Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1).offset(x: maskSize / 6)

                        // Horizontal gridlines
                        Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1).offset(y: -maskSize / 6)
                        Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1).offset(y: maskSize / 6)
                    }
                    .frame(width: maskSize, height: maskSize)
                    .clipShape(Circle())
                    .allowsHitTesting(false)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(Color.black.ignoresSafeArea())
                .clipped()
                .navigationTitle("Adjust Frame")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onCancel()
                        } label: {
                            Label("Cancel", systemImage: "xmark").fontWeight(.semibold)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            cropImage(maskSize: maskSize, baseWidth: baseWidth, baseHeight: baseHeight)
                        } label: {
                            Label("Confirm", systemImage: "checkmark").fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Clamping

    /// Valid pan range on one axis: the image can move until its edge reaches
    /// the mask's edge, never revealing blank space inside the circle.
    private func panRange(scale: CGFloat, dimension: CGFloat, maskSize: CGFloat) -> ClosedRange<CGFloat> {
        let maxOffset = max(0, (dimension * scale - maskSize) / 2)
        return -maxOffset...maxOffset
    }

    private func clampOffset(maskSize: CGFloat, baseWidth: CGFloat, baseHeight: CGFloat) {
        offset.width = offset.width.clamped(to: panRange(scale: scale, dimension: baseWidth, maskSize: maskSize))
        offset.height = offset.height.clamped(to: panRange(scale: scale, dimension: baseHeight, maskSize: maskSize))
    }

    /// UIScrollView's own rubber-band curve (coefficient 0.55): values inside `range`
    /// pass through unchanged; values past it get pulled toward the boundary with
    /// resistance that increases the further past it they go, asymptotically
    /// approaching `dimension` of extra stretch but never quite reaching it. This is
    /// what gives the live in-gesture value its elastic feel — the hard clamp only
    /// happens once the gesture ends, inside the spring animation.
    private func rubberBanded(_ value: CGFloat, range: ClosedRange<CGFloat>, dimension: CGFloat) -> CGFloat {
        guard dimension > 0 else { return value.clamped(to: range) }
        if value < range.lowerBound {
            let overshoot = range.lowerBound - value
            return range.lowerBound - rubberBandDistance(overshoot, dimension: dimension)
        }
        if value > range.upperBound {
            let overshoot = value - range.upperBound
            return range.upperBound + rubberBandDistance(overshoot, dimension: dimension)
        }
        return value
    }

    private func rubberBandDistance(_ overshoot: CGFloat, dimension: CGFloat) -> CGFloat {
        let coefficient: CGFloat = 0.55
        return (1.0 - (1.0 / ((overshoot * coefficient / dimension) + 1.0))) * dimension
    }

    // MARK: - Crop rendering

    private func cropImage(maskSize: CGFloat, baseWidth: CGFloat, baseHeight: CGFloat) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Ensure consistent scale for upload (e.g. 1x scale)
        format.opaque = true

        let targetSize = CGSize(width: maskSize, height: maskSize)
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        let cropped = renderer.image { context in
            // Fill background with black (shouldn't be visible since image fills mask, but safe)
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            // Replicates exactly what's on screen — same base-fit size, interactive
            // scale, and pan offset — into a fixed maskSize canvas. Derived so that at
            // scale == 1, offset == .zero, the image's shorter dimension exactly fills
            // the canvas edge to edge (verified against that baseline case by hand).
            let originX = targetSize.width / 2 - (baseWidth * scale) / 2 + offset.width
            let originY = targetSize.height / 2 - (baseHeight * scale) / 2 + offset.height

            context.cgContext.translateBy(x: originX, y: originY)
            context.cgContext.scaleBy(x: scale, y: scale)

            image.draw(in: CGRect(x: 0, y: 0, width: baseWidth, height: baseHeight))
        }

        onCrop(cropped)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension View {
    @inlinable func reverseMask<Mask: View>(
        alignment: Alignment = .center,
        @ViewBuilder _ mask: () -> Mask
    ) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: alignment) {
                    mask()
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

#Preview {
    // Generate a dummy image for preview
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
    let dummyImage = renderer.image { ctx in
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        UIColor.white.setFill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 40),
            .foregroundColor: UIColor.white
        ]
        let string = NSAttributedString(string: "Preview Image", attributes: attributes)
        string.draw(at: CGPoint(x: 250, y: 280))
    }

    return ImageCropView(image: dummyImage, onCrop: { _ in }, onCancel: {})
}
