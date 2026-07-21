//
//  ImageCropView.swift
//  On Board
//
//  Circular photo crop tool. Pure SwiftUI — pinch (MagnifyGesture) and pan
//  (DragGesture) drive .scaleEffect()/.offset() directly, no UIKit bridging.
//

import SwiftUI
import UIKit

struct ProfileImageCropView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var magnifyStartState: (scale: CGFloat, offset: CGSize)?

    @State private var offset: CGSize = .zero
    @State private var panStartState: (scale: CGFloat, offset: CGSize)?

    @State private var autoSettleTask: Task<Void, Never>?
    @State private var isBlurRemoved = false

    private let padding: CGFloat = 16
    private let minScale: CGFloat = 1.0
    private let doubleTapScale: CGFloat = 2.5
    private let backdropBlurRadius: CGFloat = 20

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let windowInsets = UIApplication.shared.safeAreaInsets
                let topInset = windowInsets.top + 44
                let bottomInset = windowInsets.bottom + 49
                let containerSize = CGSize(
                    width: geometry.size.width - padding * 2 - windowInsets.left - windowInsets.right,
                    height: geometry.size.height - padding * 2 - topInset - bottomInset
                )
                let maskSize = max(0, min(min(containerSize.width, containerSize.height), 600))
                let imageAspect = image.size.width / image.size.height
                let baseWidth = imageAspect > 1 ? maskSize * imageAspect : maskSize
                let baseHeight = imageAspect > 1 ? maskSize : maskSize / imageAspect
                let maxScale = maximumImageScale(baseWidth: baseWidth, maskSize: maskSize)

                ZStack {
                    Color(uiColor: .systemBackground)
                    
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: baseWidth, height: baseHeight)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: isBlurRemoved ? 0 : backdropBlurRadius)
                        .contentShape(Rectangle())
                        .gesture(
                            SimultaneousGesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        notifyInteractionStarted()
                                        if magnifyStartState == nil { magnifyStartState = (scale, offset) }
                                        guard let start = magnifyStartState else { return }
                                        
                                        let rawScale = start.scale * value.magnification
                                        let clampedScale = min(max(rawScale, minScale), maxScale)
                                        
                                        if rawScale < minScale {
                                            scale = clampedScale - (clampedScale - rawScale) * 0.3
                                        } else if rawScale > maxScale {
                                            scale = clampedScale + (rawScale - clampedScale) * 0.3
                                        } else {
                                            scale = clampedScale
                                        }
                                        
                                        let clampedOffset = clampedPanOffset(
                                            offset: start.offset,
                                            scale: scale,
                                            baseWidth: baseWidth,
                                            baseHeight: baseHeight,
                                            maskSize: maskSize
                                        )
                                        
                                        let dx = start.offset.width - clampedOffset.width
                                        let dy = start.offset.height - clampedOffset.height
                                        
                                        offset = CGSize(
                                            width: clampedOffset.width + dx * 0.3,
                                            height: clampedOffset.height + dy * 0.3
                                        )
                                    }
                                    .onEnded { _ in
                                        magnifyStartState = nil
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            clampImageTransform(maskSize: maskSize, baseWidth: baseWidth, baseHeight: baseHeight)
                                        }
                                        scheduleAutoSettle()
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        notifyInteractionStarted()
                                        if panStartState == nil { panStartState = (scale, offset) }
                                        guard let start = panStartState else { return }
                                        
                                        let rawOffset = CGSize(
                                            width: start.offset.width + value.translation.width,
                                            height: start.offset.height + value.translation.height
                                        )
                                        
                                        let clampedOffset = clampedPanOffset(
                                            offset: rawOffset,
                                            scale: scale,
                                            baseWidth: baseWidth,
                                            baseHeight: baseHeight,
                                            maskSize: maskSize
                                        )
                                        
                                        let dx = rawOffset.width - clampedOffset.width
                                        let dy = rawOffset.height - clampedOffset.height
                                        
                                        offset = CGSize(
                                            width: clampedOffset.width + dx * 0.3,
                                            height: clampedOffset.height + dy * 0.3
                                        )
                                    }
                                    .onEnded { _ in
                                        panStartState = nil
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            clampImageTransform(maskSize: maskSize, baseWidth: baseWidth, baseHeight: baseHeight)
                                        }
                                        scheduleAutoSettle()
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
                                        let maxScale = maximumImageScale(baseWidth: baseWidth, maskSize: maskSize)
                                        scale = min(doubleTapScale, maxScale)
                                        clampImageTransform(maskSize: maskSize, baseWidth: baseWidth, baseHeight: baseHeight)
                                    }
                                }
                            }
                        )

                    // The mask overlay
                    Rectangle()
                        .fill(Color(uiColor: .systemBackground).opacity(0.62))
                        .frame(width: 3000, height: 3000)
                        .reverseMask {
                            Circle()
                                .frame(width: maskSize, height: maskSize)
                        }
                        .allowsHitTesting(false)
                        
                    // Sharp image, clipped to only the circle
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: baseWidth, height: baseHeight)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .mask {
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
            .ignoresSafeArea()
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

    private func clampedPanOffset(offset: CGSize, scale: CGFloat, baseWidth: CGFloat, baseHeight: CGFloat, maskSize: CGFloat) -> CGSize {
        CGSize(
            width: offset.width.clamped(to: panRange(scale: scale, dimension: baseWidth, maskSize: maskSize)),
            height: offset.height.clamped(to: panRange(scale: scale, dimension: baseHeight, maskSize: maskSize))
        )
    }

    private func clampImageTransform(maskSize: CGFloat, baseWidth: CGFloat, baseHeight: CGFloat) {
        let maxScale = maximumImageScale(baseWidth: baseWidth, maskSize: maskSize)
        scale = min(max(scale, minScale), maxScale)
        offset = clampedPanOffset(offset: offset, scale: scale, baseWidth: baseWidth, baseHeight: baseHeight, maskSize: maskSize)
    }
    
    private func maximumImageScale(baseWidth: CGFloat, maskSize: CGFloat) -> CGFloat {
        let minImageDimension = min(image.size.width, image.size.height)
        guard minImageDimension > 0 else { return 5.0 }
        let pointsPerPixel = maskSize / minImageDimension
        let minBasePoints = 512 * pointsPerPixel
        return max(maskSize / minBasePoints, minScale)
    }

    // MARK: - Interaction State

    private func cancelAutoSettle() {
        autoSettleTask?.cancel()
        autoSettleTask = nil
    }

    private func notifyInteractionStarted() {
        cancelAutoSettle()
        if !isBlurRemoved {
            withAnimation(.easeOut(duration: 0.2)) {
                isBlurRemoved = true
            }
        }
    }

    private func scheduleAutoSettle() {
        cancelAutoSettle()
        autoSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                isBlurRemoved = false
            }
        }
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

    return ProfileImageCropView(image: dummyImage, onCrop: { _ in }, onCancel: {})
}
