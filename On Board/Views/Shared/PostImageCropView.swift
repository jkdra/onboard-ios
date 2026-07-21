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
    }

    @State private var cropRect: CGRect = .zero
    // Matches Apple's own crop tool: start framed exactly as the photo
    // already is, and let the user override with a different ratio — not
    // "Free" by default, which would visually misrepresent an uncropped
    // photo's own aspect as an arbitrary starting rect.
    @State private var selectedAspect: CropAspectOption = .original
    @State private var isPortraitOrientation = true
    @GestureState private var dragStartRect: CGRect?
    @State private var lastDisplayFrame: CGRect = .zero
    @State private var isConfirming = false

    @State private var history: [CropState] = []
    @State private var redoStack: [CropState] = []
    @State private var initialState: CropState?

    private let padding: CGFloat = 16
    private let handleVisualSize: CGFloat = 14
    private let handleHitSize: CGFloat = 44
    private let edgeHandleLength: CGFloat = 36
    private let edgeHandleThickness: CGFloat = 5
    private let settleAnimation: Animation = .smooth(duration: 0.25)
    private let confirmAnimation: Animation = .easeInOut(duration: 0.3)
    private let confirmDelay: Duration = .milliseconds(320)

    private var imageAspect: CGFloat { image.size.width / image.size.height }

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
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let containerSize = CGSize(
                        width: geometry.size.width - padding * 2,
                        height: geometry.size.height - padding * 2
                    )
                    let displayFrame = PostCropGeometry.imageDisplayFrame(imageSize: image.size, in: containerSize)
                        .offsetBy(dx: padding, dy: padding)

                    ZStack {
                        Color.clear
                            .onAppear { lastDisplayFrame = displayFrame }
                            .onChange(of: geometry.size) { _, _ in
                                lastDisplayFrame = displayFrame
                                // The container can settle to its final size a
                                // beat after first appear (e.g. mid-presentation
                                // transition) — re-snap so the crop rect doesn't
                                // stay stuck at whatever transient frame it was
                                // first computed against. Not a user action, so
                                // this doesn't push undo history.
                                cropRect = PostCropGeometry.maxRect(
                                    forAspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                                    in: displayFrame
                                )
                            }

                        Image(uiImage: image)
                            .resizable()
                            .frame(width: displayFrame.width, height: displayFrame.height)
                            .position(x: displayFrame.midX, y: displayFrame.midY)
                            .blur(radius: isConfirming ? 14 : 0)

                        Rectangle()
                            .fill(Color.black.opacity(isConfirming ? 0.85 : 0.6))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .reverseMask {
                                Rectangle().frame(width: cropRect.width, height: cropRect.height)
                                    .position(x: cropRect.midX, y: cropRect.midY)
                            }
                            .allowsHitTesting(false)

                        cropOverlay(in: displayFrame)
                            .opacity(isConfirming ? 0 : 1)
                            .allowsHitTesting(!isConfirming)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear {
                        if initialState == nil {
                            isPortraitOrientation = imageAspect <= 1
                        }
                        cropRect = PostCropGeometry.maxRect(
                            forAspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                            in: displayFrame
                        )
                        if initialState == nil {
                            initialState = currentState()
                        }
                    }
                }
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                .clipped()

                aspectPicker
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .systemBackground))
                    .opacity(isConfirming ? 0 : 1)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onCancel() } label: {
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
            }
            .onChange(of: dragStartRect) { oldValue, newValue in
                // A drag gesture (corner/edge resize or move) just ended —
                // oldValue is the snapshot captured at that gesture's start
                // (via each gesture's `if state == nil { state = cropRect }`),
                // so it's exactly the pre-drag state to push onto history.
                if let oldValue, newValue == nil {
                    pushHistory(CropState(rect: oldValue, aspect: selectedAspect, isPortrait: isPortraitOrientation))
                }
            }
        }
    }

    // MARK: - Crop rectangle + handles

    @ViewBuilder
    private func cropOverlay(in displayFrame: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            gridLines

            Color.clear
                .contentShape(Rectangle())
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(moveGesture(in: displayFrame))

            ForEach(CropCorner.allCases, id: \.self) { corner in
                handle(for: corner, in: displayFrame)
            }

            // Edge handles only make sense in Free mode — dragging a single
            // edge while an aspect ratio is locked would have to also move a
            // perpendicular edge to preserve the ratio, which defeats the
            // point of an independent-edge handle.
            if selectedAspect == .free {
                ForEach(CropEdge.allCases, id: \.self) { edge in
                    edgeHandle(for: edge, in: displayFrame)
                }
            }
        }
    }

    private var gridLines: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: cropRect.height)
                .position(x: cropRect.minX + cropRect.width / 3, y: cropRect.midY)
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: cropRect.height)
                .position(x: cropRect.minX + cropRect.width * 2 / 3, y: cropRect.midY)
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: cropRect.width, height: 1)
                .position(x: cropRect.midX, y: cropRect.minY + cropRect.height / 3)
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: cropRect.width, height: 1)
                .position(x: cropRect.midX, y: cropRect.minY + cropRect.height * 2 / 3)
        }
        .allowsHitTesting(false)
    }

    private func handle(for corner: CropCorner, in displayFrame: CGRect) -> some View {
        let point = PostCropGeometry.draggedPoint(for: corner, in: cropRect)
        return Circle()
            .fill(Color.white)
            .frame(width: handleVisualSize, height: handleVisualSize)
            .shadow(radius: 2)
            // The visible dot stays small; the actual draggable area is a
            // larger invisible hit target centered on the same point (Apple's
            // ~44pt minimum tap target), so it's easy to grab without looking oversized.
            .frame(width: handleHitSize, height: handleHitSize)
            .contentShape(Rectangle())
            .position(point)
            .gesture(resizeGesture(for: corner, in: displayFrame))
            .accessibilityLabel("Resize crop — \(corner.accessibilityDescription)")
    }

    private func edgeHandle(for edge: CropEdge, in displayFrame: CGRect) -> some View {
        let point = PostCropGeometry.edgeMidpoint(for: edge, in: cropRect)
        let isHorizontalEdge = edge == .top || edge == .bottom
        return Capsule()
            .fill(Color.white)
            .frame(
                width: isHorizontalEdge ? edgeHandleLength : edgeHandleThickness,
                height: isHorizontalEdge ? edgeHandleThickness : edgeHandleLength
            )
            .shadow(radius: 2)
            .frame(width: handleHitSize, height: handleHitSize)
            .contentShape(Rectangle())
            .position(point)
            .gesture(edgeResizeGesture(for: edge, in: displayFrame))
            .accessibilityLabel("Resize crop — \(edge.accessibilityDescription) edge")
    }

    private func resizeGesture(for corner: CropCorner, in displayFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragStartRect) { value, state, _ in
                if state == nil { state = cropRect }
            }
            .onChanged { value in
                guard let start = dragStartRect else { return }
                let anchor = PostCropGeometry.anchorPoint(for: corner, in: start)
                let origin = PostCropGeometry.draggedPoint(for: corner, in: start)
                let newPoint = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                cropRect = PostCropGeometry.rect(
                    anchor: anchor,
                    draggedPoint: newPoint,
                    aspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                    bounds: displayFrame
                )
            }
    }

    private func edgeResizeGesture(for edge: CropEdge, in displayFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragStartRect) { value, state, _ in
                if state == nil { state = cropRect }
            }
            .onChanged { value in
                guard let start = dragStartRect else { return }
                let origin = PostCropGeometry.edgeMidpoint(for: edge, in: start)
                let newPoint = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                cropRect = PostCropGeometry.resizeEdge(edge, of: start, to: newPoint, bounds: displayFrame)
            }
    }

    private func moveGesture(in displayFrame: CGRect) -> some Gesture {
        DragGesture()
            .updating($dragStartRect) { value, state, _ in
                if state == nil { state = cropRect }
            }
            .onChanged { value in
                guard let start = dragStartRect else { return }
                cropRect = PostCropGeometry.translate(start, by: value.translation, bounds: displayFrame)
            }
    }

    // MARK: - Aspect menu, orientation, undo/redo/revert

    private var aspectPicker: some View {
        HStack(spacing: 14) {
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
                    Image(systemName: "chevron.up.chevron.down")
                        .fontStyle(.caption2)
                }
                .fontStyle(.footnote)
                .fontWeight(.semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.12), in: Capsule())
            }

            if selectedAspect.supportsOrientationToggle {
                Button {
                    toggleOrientation()
                } label: {
                    Image(systemName: isPortraitOrientation ? "rectangle.portrait" : "rectangle")
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.12), in: Circle())
                }
                .accessibilityLabel(isPortraitOrientation ? "Switch to landscape" : "Switch to portrait")
            }

            Spacer()

            Button { undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(history.isEmpty)
            .accessibilityLabel("Undo")

            Button { redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(redoStack.isEmpty)
            .accessibilityLabel("Redo")

            Button { revertToOriginal() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .disabled(initialState == nil || currentState() == initialState)
            .accessibilityLabel("Revert to original")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
    }

    // MARK: - Undo / redo / revert

    private func currentState() -> CropState {
        CropState(rect: cropRect, aspect: selectedAspect, isPortrait: isPortraitOrientation)
    }

    private func pushHistory(_ state: CropState) {
        history.append(state)
        redoStack.removeAll()
    }

    private func apply(_ state: CropState) {
        withAnimation(settleAnimation) {
            selectedAspect = state.aspect
            isPortraitOrientation = state.isPortrait
            cropRect = state.rect
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
        pushHistory(currentState())
        withAnimation(settleAnimation) {
            selectedAspect = option
            cropRect = PostCropGeometry.maxRect(
                forAspect: resolvedRatio(for: option, isPortrait: isPortraitOrientation),
                in: lastDisplayFrame
            )
        }
    }

    private func toggleOrientation() {
        guard selectedAspect.supportsOrientationToggle else { return }
        pushHistory(currentState())
        isPortraitOrientation.toggle()
        withAnimation(settleAnimation) {
            cropRect = PostCropGeometry.maxRect(
                forAspect: resolvedRatio(for: selectedAspect, isPortrait: isPortraitOrientation),
                in: lastDisplayFrame
            )
        }
    }

    // MARK: - Crop rendering

    /// Plays a brief "confirming" transition (blur the surroundings, fade out
    /// the crop chrome) before actually handing back the cropped image. A
    /// scoped version of Apple's crop-confirm animation — this doesn't morph
    /// the selection into a new centered viewport, just gives a moment of
    /// visual confirmation before the sheet dismisses.
    private func beginConfirm() {
        withAnimation(confirmAnimation) {
            isConfirming = true
        }
        Task {
            try? await Task.sleep(for: confirmDelay)
            confirmCrop()
        }
    }

    private func confirmCrop() {
        // GeometryReader's displayFrame isn't available here, so we rely on
        // lastDisplayFrame, kept current by the Color.clear tracker inside
        // the GeometryReader (see onAppear/onChange(of: geometry.size) above),
        // which piggybacks on the same recomputation points cropRect depends on.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let pixelRect = PostCropGeometry.pixelRect(
            from: cropRect,
            imageDisplayFrame: lastDisplayFrame,
            imageSize: image.size
        )
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
