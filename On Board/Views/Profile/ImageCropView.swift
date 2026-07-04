//
//  ImageCropView.swift
//  On Board
//

import SwiftUI
import UIKit

struct ImageCropView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var scrollOffset: CGPoint = .zero

    private let padding: CGFloat = 16

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let maskSize = min(geometry.size.width - (padding * 2), 600)
                let imageAspect = image.size.width / image.size.height
                
                let imageWidth = imageAspect > 1 ? maskSize * imageAspect : maskSize
                let imageHeight = imageAspect > 1 ? maskSize : maskSize / imageAspect
                
                let horizontalInset = max(0, (geometry.size.width - maskSize) / 2)
                let verticalInset = max(0, (geometry.size.height - maskSize) / 2)
                
                ZStack {

                    ZoomableScrollView(
                        currentScale: $scale,
                        currentOffset: $scrollOffset,
                        doubleTapScale: 3.0,
                        contentInset: UIEdgeInsets(
                            top: verticalInset,
                            left: horizontalInset,
                            bottom: verticalInset,
                            right: horizontalInset
                        )
                    ) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: imageWidth, height: imageHeight)
                    }

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
                            Label("Cancel", systemImage: "xmark").toolbarActionLabel()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            cropImage(geometry: geometry, maskSize: maskSize, imageWidth: imageWidth, imageHeight: imageHeight)
                        } label: {
                            Label("Confirm", systemImage: "checkmark").toolbarActionLabel()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func cropImage(geometry: GeometryProxy, maskSize: CGFloat, imageWidth: CGFloat, imageHeight: CGFloat) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Ensure consistent scale for upload (e.g. 1x scale)
        format.opaque = true
        
        let targetSize = CGSize(width: maskSize, height: maskSize)
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        
        let cropped = renderer.image { context in
            // Fill background with black (shouldn't be visible since image fills mask, but safe)
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            
            let horizontalInset = max(0, (geometry.size.width - maskSize) / 2)
            let verticalInset = max(0, (geometry.size.height - maskSize) / 2)
            
            let maskOriginX = scrollOffset.x + horizontalInset
            let maskOriginY = scrollOffset.y + verticalInset
            
            context.cgContext.translateBy(x: -maskOriginX, y: -maskOriginY)
            context.cgContext.scaleBy(x: scale, y: scale)
            
            let rect = CGRect(
                x: 0,
                y: 0,
                width: imageWidth,
                height: imageHeight
            )
            
            image.draw(in: rect)
        }
        
        onCrop(cropped)
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
