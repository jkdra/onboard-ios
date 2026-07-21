//
//  PostImageCropView.swift
//  On Board
//
//  Rectangular photo crop tool for post photos: freeform (drag corner or
//  edge handles) or a preset aspect ratio (independently flippable between
//  portrait/landscape), with undo/redo/revert and a rule-of-thirds guide
//  sized to the current crop rect. Distinct from ImageCropView (circular
//  avatar crop, pan/zoom-the-image model) — here the image is static and the
//  crop rectangle itself is resized/moved, matching a Photos-app-style crop
//  tool. Inherits the system light/dark appearance rather than forcing dark.
//  Content extends full-bleed behind the translucent top/bottom bars.
//

import SwiftUI
import UIKit

enum CropAspectOption: CaseIterable, Identifiable, Equatable {
    case free, square, ratio4x5, ratio16x9, original

    var id: Self { self }

    /// Base numeric ratio (width / height) before orientation is applied.
    /// `nil` for options with no fixed ratio (`.free`) or ones resolved
    /// dynamically against the source image (`.original`).
    var baseRatio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1.0
        case .ratio4x5: return 4.0 / 5.0
        case .ratio16x9: return 16.0 / 9.0
        case .original: return nil
        }
    }

    var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .ratio4x5: return "4:5"
        case .ratio16x9: return "16:9"
        case .original: return "Original"
        }
    }

    /// Whether this option has a meaningful portrait/landscape distinction.
    /// Square is symmetric, Free has no fixed ratio, and Original always
    /// matches the source image's own orientation — none of those benefit
    /// from an independent orientation flip.
    var supportsOrientationToggle: Bool {
        switch self {
        case .ratio4x5, .ratio16x9: return true
        case .free, .square, .original: return false
        }
    }
}

struct PostImageCropView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    private struct CropState: Equatable {
        var rect: CGRect
        var aspect: CropAspectOption
        var isPortrait: Bool
        var imageScale: CGFloat
        var imageOffset: CGSize
    }

    @State private var cropRect: CGRect = .zero
    @State private var imageScale: CGFloat = 1
    @State private var imageOffset: CGSize = .zero
    // Free by default — the crop rect still starts sized to the entire
    // photo (Free has no fixed ratio, so it just fits the frame), but
    // nothing is force-selected the way a preset ratio would be.
    @State private var selectedAspect: CropAspectOption = .free
    @State private var isPortraitOrientation = true
    @GestureState private var resizeStartState: CropState?
    @GestureState private var panStartState: CropState?
    @GestureState private var magnifyStartState: CropState?
    @State private var lastDisplayFrame: CGRect = .zero
    @State private var isConfirming = false

    @State private var history: [CropState] = []
    @State private var redoStack: [CropState] = []
    @State private var initialState: CropState?
    @State private var interaction = CropInteractionState()

    private let padding: CGFloat = 16
    private let handleHitSize: CGFloat = 44
    private let edgeHandleLength: CGFloat = 36
    private let edgeHandleThickness: CGFloat = 5
    private let backdropBlurRadius: CGFloat = 20
    private let settleAnimation: Animation = .smooth(duration: 0.25)
    private let autoSettleAnimation: Animation = .smooth(duration: 0.35)
    private let confirmAnimation: Animation = .easeInOut(duration: 0.3)
    private let confirmDelay: Duration = .milliseconds(320)
    // The crop output is never allowed below this on its shorter side, in
    // source-image pixels — so a user can't drag the selection down to a
    // uselessly tiny region. Clamped to the image if it's smaller than this.
    private let minOutputResolution: CGFloat = 640

    private var imageAspect: CGFloat { image.size.width / image.size.height }

    /// The minimum crop-rect side, in on-screen points, that still yields at
    /// least `minOutputResolution` source-image pixels. It follows the
    /// effective (possibly zoomed) image frame, not the untransformed base.
    private func minCropDimensionInPoints(for imageRect: CGRect) -> CGFloat {
        guard imageRect.width > 0, image.size.width > 0 else {
            return CropGeometry.minCropDimension
        }
        let pointsPerPixel = imageRect.width / image.size.width
        return minOutputResolution * pointsPerPixel
    }

    private func minimumImageScale(for baseFrame: CGRect) -> CGFloat {
        CropGeometry.minScaleToCover(base: baseFrame, cropRect: cropRect)
    }

    private func maximumImageScale(for baseFrame: CGRect) -> CGFloat {
        guard baseFrame.width > 0, image.size.width > 0 else { return 100 }
        let basePointsPerPixel = baseFrame.width / image.size.width
        let minBasePoints = minOutputResolution * basePointsPerPixel
        let minCropDimension = min(cropRect.width, cropRect.height)
        return max(minCropDimension / minBasePoints, minimumImageScale(for: baseFrame))
    }

    /// `.original` isn't a fixed ratio — it's whatever the source image's own
    /// aspect is. Other directional options normalize their base ratio to
    /// whichever orientation is currently selected, regardless of which
    /// orientation the base ratio was originally defined in.
    private func resolvedRatio(for option: CropAspectOption, isPortrait: Bool) -> CGFloat? {
        if option == .original { return imageAspect }
        guard let base = option.baseRatio else { return nil }
        guard option.supportsOrientationToggle else { return base }
        return isPortrait ? min(base, 1 / base) : max(base, 1 / base)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let windowInsets = UIApplication.shared.safeAreaInsets
                let navBarHeight: CGFloat = 44
                let topInset = windowInsets.top + navBarHeight
                
                let containerSize = CropGeometry.containerSize(for: geometry.size, safeAreaInsets: windowInsets)
                let displayFrame = CropGeometry.imageDisplayFrame(imageSize: image.size, in: containerSize)
                    .offsetBy(dx: padding + windowInsets.left, dy: padding + topInset)
                let effectiveImageFrame = CropGeometry.effectiveImageRect(
                    base: displayFrame,
                    scale: imageScale,
                    offset: imageOffset
                )

                ZStack {
                    Color(uiColor: .systemBackground)
                        .onAppear { lastDisplayFrame = displayFrame }
                        .onChange(of: geometry.size) { _, _ in
                            lastDisplayFrame = displayFrame
                            // The container can settle to its final size a
                            // beat after first appear (e.g. mid-presentation
                            // transition) — re-snap so the crop rect doesn't
                            // stay stuck at whatever transient frame it was
                            // first computed against. Not a user action, so
                            // this doesn't push undo history.
                            cropRect = CropGeometry.maxRect(
                                forAspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                                in: displayFrame
                            )
                            imageScale = 1
                            imageOffset = .zero
                        }

                    // Blurred backdrop, visible everywhere — the sharp layer
                    // below covers it entirely within the crop rect, so this
                    // only ever shows through in the masked-out area.
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: displayFrame.width, height: displayFrame.height)
                        .scaleEffect(imageScale)
                        .offset(imageOffset)
                        .position(x: displayFrame.midX, y: displayFrame.midY)
                        .blur(radius: interaction.isBlurRemoved ? 0 : backdropBlurRadius)
                        .clipped()

                    // systemBackground so the masked-out area reads as white
                    // in light mode / black in dark mode automatically, over
                    // the blurred backdrop below it.
                    Rectangle()
                        .fill(Color(uiColor: .systemBackground).opacity(0.75))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .reverseMask {
                            Rectangle().frame(width: cropRect.width, height: cropRect.height)
                                .position(x: cropRect.midX, y: cropRect.midY)
                        }
                        .allowsHitTesting(false)

                    // Sharp image, clipped to only the crop rect.
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: displayFrame.width, height: displayFrame.height)
                        .scaleEffect(imageScale)
                        .offset(imageOffset)
                        .position(x: displayFrame.midX, y: displayFrame.midY)
                        .mask {
                            Rectangle().frame(width: cropRect.width, height: cropRect.height)
                                .position(x: cropRect.midX, y: cropRect.midY)
                        }
                        .blur(radius: isConfirming ? 14 : 0)
                        .allowsHitTesting(false)

                    cropOverlay(in: effectiveImageFrame, baseFrame: displayFrame)
                        .opacity(isConfirming ? 0 : 1)
                        .allowsHitTesting(!isConfirming)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear {
                    if initialState == nil {
                        isPortraitOrientation = imageAspect <= 1
                    }
                    cropRect = CropGeometry.maxRect(
                        forAspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                        in: displayFrame
                    )
                    imageScale = 1
                    imageOffset = .zero
                    if initialState == nil {
                        initialState = currentState()
                    }
                }
            }
            .onDisappear { interaction.cancelAutoSettle() }
            .ignoresSafeArea()
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        interaction.cancelAutoSettle()
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark").fontWeight(.semibold)
                    }
                    .disabled(isConfirming)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { beginConfirm() } label: {
                        Label("Confirm", systemImage: "checkmark").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConfirming)
                }
                ToolbarItem(placement: .bottomBar) {
                    aspectMenu
                        .disabled(isConfirming)
                }
                if selectedAspect.supportsOrientationToggle {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            toggleOrientation()
                        } label: {
                            Image(systemName: isPortraitOrientation ? "rectangle.portrait" : "rectangle")
                        }
                        .disabled(isConfirming)
                        .accessibilityLabel(isPortraitOrientation ? "Switch to landscape" : "Switch to portrait")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(history.isEmpty || isConfirming)
                    .accessibilityLabel("Undo")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(redoStack.isEmpty || isConfirming)
                    .accessibilityLabel("Redo")
                }
            }
            .toolbar(isConfirming ? .hidden : .visible, for: .bottomBar)
            .onChange(of: resizeStartState) { oldValue, newValue in
                if let oldValue, newValue == nil {
                    pushHistory(oldValue)
                }
            }
            .onChange(of: panStartState) { oldValue, newValue in
                if let oldValue, newValue == nil {
                    pushHistory(oldValue)
                }
            }
            .onChange(of: magnifyStartState) { oldValue, newValue in
                if let oldValue, newValue == nil {
                    pushHistory(oldValue)
                }
            }
        }
    }

    // MARK: - Crop rectangle + handles

    @ViewBuilder
    private func cropOverlay(in imageFrame: CGRect, baseFrame: CGRect) -> some View {
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

    private var aspectMenu: some View {
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

    // MARK: - Undo / redo / revert

    private func currentState() -> CropState {
        CropState(
            rect: cropRect,
            aspect: selectedAspect,
            isPortrait: isPortraitOrientation,
            imageScale: imageScale,
            imageOffset: imageOffset
        )
    }

    private func pushHistory(_ state: CropState) {
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

    private func undo() {
        guard let previous = history.popLast() else { return }
        redoStack.append(currentState())
        apply(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        history.append(currentState())
        apply(next)
    }

    private func revertToOriginal() {
        guard let initialState, currentState() != initialState else { return }
        pushHistory(currentState())
        apply(initialState)
    }

    private func selectAspect(_ option: CropAspectOption) {
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

    private func toggleOrientation() {
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
    private func beginConfirm() {
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

#Preview {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
    let dummyImage = renderer.image { ctx in
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
    }
    return PostImageCropView(image: dummyImage, onCrop: { _ in }, onCancel: {})
}

extension UIApplication {
    var safeAreaInsets: UIEdgeInsets {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
}

