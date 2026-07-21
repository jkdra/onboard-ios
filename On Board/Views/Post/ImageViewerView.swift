import SwiftUI
import NukeUI
import Nuke

struct ImageViewerView<ID: Hashable>: View {
    let url: URL?
    let namespace: Namespace.ID
    let sourceID: ID
    @Binding var isPresented: Bool
    var aspectRatio: CGFloat? = nil
    var currentScale: Binding<CGFloat>? = nil

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var magnifyStartState: (scale: CGFloat, offset: CGSize)?
    @State private var panStartState: (scale: CGFloat, offset: CGSize)?
    @State private var loadedImageSize: CGSize?
    
    // Background opacity tied to swipe-down distance
    @State private var backgroundOpacity: Double = 1.0

    private let minScale: CGFloat = 1.0
    private let doubleTapScale: CGFloat = 2.5
    private let dismissThreshold: CGFloat = 100 // Drag down by 100pt to dismiss
    
    private var resolvedAspectRatio: CGFloat? {
        if let aspect = aspectRatio { return aspect }
        if let size = loadedImageSize { return size.width / size.height }
        return nil
    }

    var body: some View {
        ZStack {
            if isPresented, let url = url {
                Color.black
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)
                    .transition(.opacity)

                GeometryReader { proxy in
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .scaledToFit()
                                .onAppear {
                                    if let size = state.imageContainer?.image.size {
                                        loadedImageSize = size
                                    }
                                }
                        } else if state.error != nil {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.5))
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .aspectRatio(resolvedAspectRatio, contentMode: .fit)
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                    .matchedGeometryEffect(id: sourceID, in: namespace)
                    .transition(.identity)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    if magnifyStartState == nil { magnifyStartState = (scale, offset) }
                                    guard let start = magnifyStartState else { return }
                                    
                                    // Max scale derived from the proxy to allow ~4x zooming
                                    let maxScale: CGFloat = 4.0
                                    
                                    scale = CropGeometry.rubberBandedScale(
                                        raw: start.scale * value.magnification,
                                        min: minScale,
                                        max: maxScale
                                    )
                                    
                                    let clampedOffset = clampedPanOffset(
                                        offset: start.offset,
                                        scale: scale,
                                        containerSize: proxy.size,
                                        imageSize: loadedImageSize ?? proxy.size
                                    )
                                    
                                    offset = CropGeometry.rubberBandedOffset(raw: start.offset, clamped: clampedOffset)
                                }
                                .onEnded { _ in
                                    magnifyStartState = nil
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        clampImageTransform(containerSize: proxy.size, imageSize: loadedImageSize ?? proxy.size)
                                    }
                                },
                            DragGesture()
                                .onChanged { value in
                                    // If at 1.0 scale, dragging down acts as a swipe-to-dismiss
                                    if scale <= minScale + 0.05 {
                                        let dragAmount = value.translation.height
                                        if dragAmount > 0 {
                                            // Pulling down
                                            offset = value.translation
                                            // Dim the background proportionally
                                            backgroundOpacity = max(0, 1.0 - (dragAmount / dismissThreshold) * 0.5)
                                            
                                            // Also slightly shrink the image as it's pulled down
                                            let shrinkScale = max(0.8, 1.0 - (dragAmount / (dismissThreshold * 4)))
                                            scale = shrinkScale
                                        }
                                        return
                                    }
                                    
                                    // Normal panning when zoomed
                                    if panStartState == nil { panStartState = (scale, offset) }
                                    guard let start = panStartState else { return }
                                    
                                    let rawOffset = CGSize(
                                        width: start.offset.width + value.translation.width,
                                        height: start.offset.height + value.translation.height
                                    )
                                    
                                    let clampedOffset = clampedPanOffset(
                                        offset: rawOffset,
                                        scale: scale,
                                        containerSize: proxy.size,
                                        imageSize: loadedImageSize ?? proxy.size
                                    )
                                    
                                    offset = CropGeometry.rubberBandedOffset(raw: rawOffset, clamped: clampedOffset)
                                }
                                .onEnded { value in
                                    // Handle swipe-to-dismiss resolution
                                    if scale < minScale {
                                        if value.translation.height > dismissThreshold || value.predictedEndTranslation.height > dismissThreshold {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                isPresented = false
                                            }
                                        } else {
                                            // Snap back
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                scale = minScale
                                                offset = .zero
                                                backgroundOpacity = 1.0
                                            }
                                        }
                                        return
                                    }
                                    
                                    // Normal panning resolution
                                    panStartState = nil
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        clampImageTransform(containerSize: proxy.size, imageSize: loadedImageSize ?? proxy.size)
                                    }
                                }
                        )
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if scale > minScale {
                                    scale = minScale
                                    offset = .zero
                                } else {
                                    scale = doubleTapScale
                                    clampImageTransform(containerSize: proxy.size, imageSize: loadedImageSize ?? proxy.size)
                                }
                            }
                        }
                    )
                }
            }
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                scale = 1.0
                offset = .zero
                backgroundOpacity = 1.0
                magnifyStartState = nil
                panStartState = nil
                currentScale?.wrappedValue = 1.0
            }
        }
        .onChange(of: scale) { _, newScale in
            currentScale?.wrappedValue = newScale
        }
    }

    // MARK: - Smart Clamping Math

    /// Ensures the image cannot be dragged off-center on any axis where it is smaller than the screen.
    private func clampedPanOffset(offset: CGSize, scale: CGFloat, containerSize: CGSize, imageSize: CGSize) -> CGSize {
        // Calculate the physical size of the image on screen at 1.0x scale
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        var baseWidth: CGFloat
        var baseHeight: CGFloat
        
        if imageAspect > containerAspect {
            // Image is wider than container (letterboxed top/bottom)
            baseWidth = containerSize.width
            baseHeight = containerSize.width / imageAspect
        } else {
            // Image is taller than container (pillarboxed left/right)
            baseHeight = containerSize.height
            baseWidth = containerSize.height * imageAspect
        }
        
        // Calculate the maximum allowed offset per axis
        // If the scaled dimension is less than the container, maxOffset is clamped to 0 (perfectly centered)
        let maxOffsetX = max(0, (baseWidth * scale - containerSize.width) / 2)
        let maxOffsetY = max(0, (baseHeight * scale - containerSize.height) / 2)
        
        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    private func clampImageTransform(containerSize: CGSize, imageSize: CGSize) {
        let maxScale: CGFloat = 4.0
        scale = min(max(scale, minScale), maxScale)
        offset = clampedPanOffset(offset: offset, scale: scale, containerSize: containerSize, imageSize: imageSize)
    }
}
