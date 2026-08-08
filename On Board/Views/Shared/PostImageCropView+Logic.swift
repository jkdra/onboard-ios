//
//  PostImageCropView+Logic.swift
//  On Board
//
//  Undo/redo/revert history and the crop-confirm rendering path, split out
//  of PostImageCropView.swift along its own MARKs. The state these mutate
//  stays as stored properties in the core file.
//

import SwiftUI
import UIKit

extension PostImageCropView {

    // MARK: - Undo / redo / revert

    func currentState() -> CropState {
        CropState(
            rect: cropRect,
            aspect: selectedAspect,
            isPortrait: isPortraitOrientation,
            imageScale: imageScale,
            imageOffset: imageOffset
        )
    }

    func pushHistory(_ state: CropState) {
        history.append(state)
        redoStack.removeAll()
    }

    private func apply(_ state: CropState) {
        interaction.cancelAutoSettle()
        withAnimation(settleAnimation) {
            selectedAspect = state.aspect
            isPortraitOrientation = state.isPortrait
            cropRect = state.rect
            imageScale = state.imageScale
            imageOffset = state.imageOffset
        }
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        redoStack.append(currentState())
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        history.append(currentState())
        apply(next)
    }

    func revertToOriginal() {
        guard let initialState, currentState() != initialState else { return }
        pushHistory(currentState())
        apply(initialState)
    }

    func selectAspect(_ option: CropAspectOption) {
        guard option != selectedAspect else { return }
        interaction.cancelAutoSettle()
        pushHistory(currentState())
        withAnimation(settleAnimation) {
            selectedAspect = option
            cropRect = CropGeometry.maxRect(
                forAspect: resolvedRatio(for: option, isPortrait: isPortraitOrientation),
                in: lastDisplayFrame
            )
            imageScale = 1
            imageOffset = .zero
        }
    }

    func toggleOrientation() {
        guard selectedAspect.supportsOrientationToggle else { return }
        interaction.cancelAutoSettle()
        pushHistory(currentState())
        isPortraitOrientation.toggle()
        withAnimation(settleAnimation) {
            cropRect = CropGeometry.maxRect(
                forAspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                in: lastDisplayFrame
            )
            imageScale = 1
            imageOffset = .zero
        }
    }

    // MARK: - Crop rendering

    /// Plays a brief "confirming" transition (blur the surroundings further,
    /// fade out the crop chrome) before actually handing back the cropped
    /// image. A scoped version of Apple's crop-confirm animation — this
    /// doesn't morph the selection into a new centered viewport, just gives
    /// a moment of visual confirmation before the sheet dismisses.
    func beginConfirm() {
        interaction.cancelAutoSettle()
        withAnimation(confirmAnimation) {
            isConfirming = true
        }
        Task {
            try? await Task.sleep(for: confirmDelay)
            confirmCrop()
        }
    }

    private func confirmCrop() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let imageFrame = CropGeometry.effectiveImageRect(
            base: lastDisplayFrame,
            scale: imageScale,
            offset: imageOffset
        )
        let normalized = CropGeometry.normalizedCrop(cropRect: cropRect, imageRect: imageFrame)
        let pixelRect = CropGeometry.pixelRect(normalizedCrop: normalized, imageSize: image.size).integral
        guard pixelRect.width > 0, pixelRect.height > 0 else { return }
        let renderer = UIGraphicsImageRenderer(size: pixelRect.size, format: format)
        let cropped = renderer.image { _ in
            image.draw(at: CGPoint(x: -pixelRect.origin.x, y: -pixelRect.origin.y))
        }
        onCrop(cropped)
    }
}
