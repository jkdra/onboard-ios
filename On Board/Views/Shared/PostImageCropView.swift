//
//  PostImageCropView.swift
//  On Board
//
//  Rectangular photo crop tool for post photos: freeform (drag corner
//  handles) or a preset aspect ratio, with a rule-of-thirds guide sized to
//  the current crop rect. Distinct from ImageCropView (circular avatar crop,
//  pan/zoom-the-image model) — here the image is static and the crop
//  rectangle itself is resized/moved, matching a Photos-app-style crop tool.
//

import SwiftUI
import UIKit

enum CropAspectOption: CaseIterable, Identifiable {
    case free, square, portrait45, landscape169, original

    var id: Self { self }

    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1.0
        case .portrait45: return 4.0 / 5.0
        case .landscape169: return 16.0 / 9.0
        case .original: return nil // resolved against the image's own aspect at use site
        }
    }

    var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .portrait45: return "4:5"
        case .landscape169: return "16:9"
        case .original: return "Original"
        }
    }
}

struct PostImageCropView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var cropRect: CGRect = .zero
    @State private var selectedAspect: CropAspectOption = .free
    @State private var dragStartRect: CGRect?
    @State private var lastDisplayFrame: CGRect = .zero

    private let padding: CGFloat = 16
    private let handleSize: CGFloat = 28
    private let settleAnimation: Animation = .smooth(duration: 0.25)

    private var imageAspect: CGFloat { image.size.width / image.size.height }

    /// `.original` isn't a fixed ratio — it's whatever the source image's own aspect is.
    private func resolvedRatio(for option: CropAspectOption) -> CGFloat? {
        option == .original ? imageAspect : option.ratio
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
                            .onChange(of: geometry.size) { _, _ in lastDisplayFrame = displayFrame }

                        Image(uiImage: image)
                            .resizable()
                            .frame(width: displayFrame.width, height: displayFrame.height)
                            .position(x: displayFrame.midX, y: displayFrame.midY)

                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .reverseMask {
                                Rectangle().frame(width: cropRect.width, height: cropRect.height)
                                    .position(x: cropRect.midX, y: cropRect.midY)
                            }
                            .allowsHitTesting(false)

                        cropOverlay(in: displayFrame)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear {
                        cropRect = PostCropGeometry.maxRect(forAspect: resolvedRatio(for: selectedAspect), in: displayFrame)
                    }
                    .onChange(of: selectedAspect) { _, newValue in
                        withAnimation(settleAnimation) {
                            cropRect = PostCropGeometry.maxRect(forAspect: resolvedRatio(for: newValue), in: displayFrame)
                        }
                    }
                }
                .background(Color.black.ignoresSafeArea())
                .clipped()

                aspectPicker
                    .padding(.vertical, 14)
                    .background(Color.black)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onCancel() } label: {
                        Label("Cancel", systemImage: "xmark").fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { confirmCrop() } label: {
                        Label("Confirm", systemImage: "checkmark").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .preferredColorScheme(.dark)
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
            .frame(width: handleSize, height: handleSize)
            .shadow(radius: 2)
            .position(point)
            .gesture(resizeGesture(for: corner, in: displayFrame))
            .accessibilityLabel("Resize crop — \(corner)")
    }

    private func resizeGesture(for corner: CropCorner, in displayFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = start }
                let anchor = PostCropGeometry.anchorPoint(for: corner, in: start)
                let origin = PostCropGeometry.draggedPoint(for: corner, in: start)
                let newPoint = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                cropRect = PostCropGeometry.rect(
                    anchor: anchor,
                    draggedPoint: newPoint,
                    aspect: resolvedRatio(for: selectedAspect),
                    bounds: displayFrame
                )
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func moveGesture(in displayFrame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = start }
                cropRect = PostCropGeometry.translate(start, by: value.translation, bounds: displayFrame)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    // MARK: - Aspect picker

    private var aspectPicker: some View {
        HStack(spacing: 10) {
            ForEach(CropAspectOption.allCases) { option in
                Button {
                    selectedAspect = option
                } label: {
                    Text(option.label)
                        .fontStyle(.footnote)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedAspect == option ? Color.white : Color.white.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedAspect == option ? .black : .white)
                }
            }
        }
    }

    // MARK: - Crop rendering

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

#Preview {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
    let dummyImage = renderer.image { ctx in
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
    }
    return PostImageCropView(image: dummyImage, onCrop: { _ in }, onCancel: {})
}
