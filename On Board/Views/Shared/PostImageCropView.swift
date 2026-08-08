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
//  Split across files: `CropAspectOption.swift` (aspect presets),
//  `PostImageCropView+Views.swift` (crop overlay/handles/gestures + aspect
//  menu), `PostImageCropView+Logic.swift` (undo/redo/revert + crop
//  rendering). The stored state and layout constants those extensions use
//  live here and are `internal` (not `private`) solely for that reason —
//  extensions in other files can't reach private members.
//

import SwiftUI
import UIKit

struct PostImageCropView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    struct CropState: Equatable {
        var rect: CGRect
        var aspect: CropAspectOption
        var isPortrait: Bool
        var imageScale: CGFloat
        var imageOffset: CGSize
    }

    @State var cropRect: CGRect = .zero
    @State var imageScale: CGFloat = 1
    @State var imageOffset: CGSize = .zero
    // Free by default — the crop rect still starts sized to the entire
    // photo (Free has no fixed ratio, so it just fits the frame), but
    // nothing is force-selected the way a preset ratio would be.
    @State var selectedAspect: CropAspectOption = .free
    @State var isPortraitOrientation = true
    @GestureState var resizeStartState: CropState?
    @GestureState var panStartState: CropState?
    @GestureState var magnifyStartState: CropState?
    @State var lastDisplayFrame: CGRect = .zero
    @State var isConfirming = false

    @State var history: [CropState] = []
    @State var redoStack: [CropState] = []
    @State var initialState: CropState?
    @State var interaction = CropInteractionState()

    private let padding: CGFloat = 16
    let handleHitSize: CGFloat = 44
    let edgeHandleLength: CGFloat = 36
    let edgeHandleThickness: CGFloat = 5
    private let backdropBlurRadius: CGFloat = 20
    let settleAnimation: Animation = .smooth(duration: 0.25)
    let autoSettleAnimation: Animation = .smooth(duration: 0.35)
    let confirmAnimation: Animation = .easeInOut(duration: 0.3)
    let confirmDelay: Duration = .milliseconds(320)
    // The crop output is never allowed below this on its shorter side, in
    // source-image pixels — so a user can't drag the selection down to a
    // uselessly tiny region. Clamped to the image if it's smaller than this.
    private let minOutputResolution: CGFloat = 640

    private var imageAspect: CGFloat { image.size.width / image.size.height }

    /// The minimum crop-rect side, in on-screen points, that still yields at
    /// least `minOutputResolution` source-image pixels. It follows the
    /// effective (possibly zoomed) image frame, not the untransformed base.
    func minCropDimensionInPoints(for imageRect: CGRect) -> CGFloat {
        guard imageRect.width > 0, image.size.width > 0 else {
            return CropGeometry.minCropDimension
        }
        let pointsPerPixel = imageRect.width / image.size.width
        return minOutputResolution * pointsPerPixel
    }

    func minimumImageScale(for baseFrame: CGRect) -> CGFloat {
        CropGeometry.minScaleToCover(base: baseFrame, cropRect: cropRect)
    }

    func maximumImageScale(for baseFrame: CGRect) -> CGFloat {
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
    func resolvedRatio(for option: CropAspectOption, isPortrait: Bool) -> CGFloat? {
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
}

#Preview {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
    let dummyImage = renderer.image { ctx in
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
    }
    return PostImageCropView(image: dummyImage, onCrop: { _ in }, onCancel: {})
}
