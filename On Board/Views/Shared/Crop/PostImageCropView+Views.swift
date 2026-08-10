//
//  PostImageCropView+Views.swift
//  On Board
//
//  Crop-rect overlay, handles, and their gestures, plus the aspect menu —
//  split out of PostImageCropView.swift along its own MARKs. The state these
//  read (@State/@GestureState/layout constants) stays as stored properties in
//  the core file; this split is why those are `internal` there.
//

import SwiftUI
import UIKit

extension PostImageCropView {

    // MARK: - Crop rectangle + handles

    @ViewBuilder
    func cropOverlay(in imageFrame: CGRect, baseFrame: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.primary.opacity(0.7), lineWidth: 1)
                .compositingGroup()
                .shadow(color: .black.opacity(0.4), radius: 1)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .allowsHitTesting(false)

            gridLines

            Color.clear
                .contentShape(Rectangle())
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(imageTransformGesture(baseFrame: baseFrame))

            ForEach(CropCorner.allCases, id: \.self) { corner in
                handle(for: corner, in: imageFrame)
            }

            ForEach(CropEdge.allCases, id: \.self) { edge in
                edgeHandle(for: edge, in: imageFrame)
            }
        }
    }

    private var gridLines: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1, height: cropRect.height)
                .position(x: cropRect.minX + cropRect.width / 3, y: cropRect.midY)
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1, height: cropRect.height)
                .position(x: cropRect.minX + cropRect.width * 2 / 3, y: cropRect.midY)
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: cropRect.width, height: 1)
                .position(x: cropRect.midX, y: cropRect.minY + cropRect.height / 3)
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: cropRect.width, height: 1)
                .position(x: cropRect.midX, y: cropRect.minY + cropRect.height * 2 / 3)
        }
        .allowsHitTesting(false)
    }

    private func handle(for corner: CropCorner, in displayFrame: CGRect) -> some View {
        let point = CropGeometry.draggedPoint(for: corner, in: cropRect)
        return Color.clear
            .frame(width: handleHitSize, height: handleHitSize)
            .contentShape(Rectangle())
            .position(point)
            .gesture(resizeGesture(for: corner, in: displayFrame))
            .accessibilityLabel("Resize crop — \(corner.accessibilityDescription)")
    }

    private func edgeHandle(for edge: CropEdge, in displayFrame: CGRect) -> some View {
        let point = CropGeometry.edgeMidpoint(for: edge, in: cropRect)
        let isHorizontalEdge = edge == .top || edge == .bottom
        return RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.primary)
            .frame(
                width: isHorizontalEdge ? edgeHandleLength : edgeHandleThickness,
                height: isHorizontalEdge ? edgeHandleThickness : edgeHandleLength
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.5), radius: 1.5)
            .frame(width: handleHitSize, height: handleHitSize)
            .contentShape(Rectangle())
            .position(point)
            .gesture(edgeResizeGesture(for: edge, in: displayFrame))
            .accessibilityLabel("Resize crop — \(edge.accessibilityDescription) edge")
    }

    private func resizeGesture(for corner: CropCorner, in imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($resizeStartState) { _, state, _ in
                if state == nil { state = currentState() }
            }
            .onChanged { value in
                interaction.notifyInteractionStarted()
                guard let start = resizeStartState else { return }
                let anchor = CropGeometry.anchorPoint(for: corner, in: start.rect)
                let origin = CropGeometry.draggedPoint(for: corner, in: start.rect)
                let newPoint = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                cropRect = CropGeometry.rect(
                    anchor: anchor,
                    draggedPoint: newPoint,
                    aspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                    bounds: imageFrame,
                    minDimension: minCropDimensionInPoints(for: imageFrame)
                )
            }
            .onEnded { _ in interaction.scheduleAutoSettle(onSettle: { self.autoSettle() }) }
    }

    private func edgeResizeGesture(for edge: CropEdge, in imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($resizeStartState) { _, state, _ in
                if state == nil { state = currentState() }
            }
            .onChanged { value in
                interaction.notifyInteractionStarted()
                guard let start = resizeStartState else { return }
                let origin = CropGeometry.edgeMidpoint(for: edge, in: start.rect)
                let newPoint = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                cropRect = CropGeometry.resizeEdge(
                    edge,
                    of: start.rect,
                    to: newPoint,
                    aspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                    bounds: imageFrame,
                    minDimension: minCropDimensionInPoints(for: imageFrame)
                )
            }
            .onEnded { _ in interaction.scheduleAutoSettle(onSettle: { self.autoSettle() }) }
    }

    private func imageTransformGesture(baseFrame: CGRect) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .updating($panStartState) { _, state, _ in
                    if state == nil { state = currentState() }
                }
                .onChanged { value in
                    interaction.notifyInteractionStarted()
                    guard let start = panStartState else { return }

                    let rawOffset = CGSize(
                        width: start.imageOffset.width + value.translation.width,
                        height: start.imageOffset.height + value.translation.height
                    )

                    let clampedOffset = CropGeometry.clampOffsetToCover(
                        offset: rawOffset,
                        base: baseFrame,
                        scale: imageScale,
                        cropRect: cropRect
                    )

                    imageOffset = CropGeometry.rubberBandedOffset(raw: rawOffset, clamped: clampedOffset)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        clampImageTransform(to: baseFrame)
                    }
                    interaction.scheduleAutoSettle(onSettle: { self.autoSettle() })
                },
            MagnifyGesture()
                .updating($magnifyStartState) { _, state, _ in
                    if state == nil { state = currentState() }
                }
                .onChanged { value in
                    interaction.notifyInteractionStarted()
                    guard let start = magnifyStartState else { return }
                    let minScale = minimumImageScale(for: baseFrame)
                    let maxScale = maximumImageScale(for: baseFrame)

                    imageScale = CropGeometry.rubberBandedScale(
                        raw: start.imageScale * value.magnification,
                        min: minScale,
                        max: maxScale
                    )

                    let clampedOffset = CropGeometry.clampOffsetToCover(
                        offset: start.imageOffset,
                        base: baseFrame,
                        scale: imageScale,
                        cropRect: cropRect
                    )

                    imageOffset = CropGeometry.rubberBandedOffset(raw: start.imageOffset, clamped: clampedOffset)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        clampImageTransform(to: baseFrame)
                    }
                    interaction.scheduleAutoSettle(onSettle: { self.autoSettle() })
                }
        )
    }

    private func clampImageTransform(to baseFrame: CGRect) {
        let minScale = minimumImageScale(for: baseFrame)
        let maxScale = maximumImageScale(for: baseFrame)
        imageScale = min(max(imageScale, minScale), maxScale)
        imageOffset = CropGeometry.clampOffsetToCover(
            offset: imageOffset,
            base: baseFrame,
            scale: imageScale,
            cropRect: cropRect
        )
    }

    private func autoSettle() {
        guard lastDisplayFrame.width > 0, lastDisplayFrame.height > 0 else { return }
        let imageFrame = CropGeometry.effectiveImageRect(
            base: lastDisplayFrame,
            scale: imageScale,
            offset: imageOffset
        )
        let normalized = CropGeometry.normalizedCrop(cropRect: cropRect, imageRect: imageFrame)
        guard normalized.width > 0, normalized.height > 0 else { return }
        let layout = CropGeometry.normalizedLayout(
            normalizedCrop: normalized,
            base: lastDisplayFrame,
            viewport: lastDisplayFrame
        )
        withAnimation(autoSettleAnimation) {
            cropRect = layout.cropRect
            imageScale = layout.scale
            imageOffset = layout.offset
        }
    }

    // MARK: - Aspect menu

    var aspectMenu: some View {
        Menu {
            ForEach(CropAspectOption.allCases) { option in
                Button {
                    selectAspect(option)
                } label: {
                    if selectedAspect == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedAspect.label)
                    .fontStyle(.subheadline)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .fontStyle(.caption2)
            }
        }
    }
}

private extension CropCorner {
    /// Human-readable form for accessibility labels — interpolating the raw
    /// enum case directly triggers a deprecated, unlocalized debug-description
    /// path in SwiftUI's LocalizedStringKey interpolation.
    var accessibilityDescription: String {
        switch self {
        case .topLeft: "top-left"
        case .topRight: "top-right"
        case .bottomLeft: "bottom-left"
        case .bottomRight: "bottom-right"
        }
    }
}

private extension CropEdge {
    var accessibilityDescription: String {
        switch self {
        case .top: "top"
        case .bottom: "bottom"
        case .left: "left"
        case .right: "right"
        }
    }
}
