import SwiftUI

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content
    
    // Bindings to expose the current state (useful for cropping)
    @Binding var currentScale: CGFloat
    @Binding var currentOffset: CGPoint
    
    // Configurable properties
    var doubleTapScale: CGFloat = 2.0
    var contentInset: UIEdgeInsets = .zero
    
    init(
        currentScale: Binding<CGFloat> = .constant(1.0),
        currentOffset: Binding<CGPoint> = .constant(.zero),
        doubleTapScale: CGFloat = 2.0,
        contentInset: UIEdgeInsets = .zero,
        @ViewBuilder content: () -> Content
    ) {
        self._currentScale = currentScale
        self._currentOffset = currentOffset
        self.doubleTapScale = doubleTapScale
        self.contentInset = contentInset
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = contentInset
        
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        
        scrollView.addSubview(hostingController.view)
        context.coordinator.hostingController = hostingController
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        ])
        
        // Double tap gesture
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingController?.rootView = content
        
        if uiView.contentInset != contentInset {
            uiView.contentInset = contentInset
        }
        
        // Note: we don't sync external state to the scroll view here because 
        // it causes stuttering. The scroll view is the source of truth.
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableScrollView
        var hostingController: UIHostingController<Content>?
        
        init(_ parent: ZoomableScrollView) {
            self.parent = parent
        }
        
        // Explicit (if empty) — Xcode Cloud's Swift 6.3.2 crashes in the
        // EarlyPerfInliner SIL pass while inlining the *synthesized* deinit for
        // this generic-nested class (release build, whole-module optimization
        // only). Behavior is identical either way; this just avoids the
        // compiler-generated deinit path that pass trips on.
        deinit {}
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController?.view
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Keep the view centered if zoomed out or if content is smaller than bounds
            if let view = hostingController?.view {
                let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
                let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
                view.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX,
                                      y: scrollView.contentSize.height * 0.5 + offsetY)
            }
            
            let newScale = scrollView.zoomScale
            let newOffset = scrollView.contentOffset
            
            if parent.currentScale != newScale || parent.currentOffset != newOffset {
                DispatchQueue.main.async {
                    self.parent.currentScale = newScale
                    self.parent.currentOffset = newOffset
                }
            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let newOffset = scrollView.contentOffset
            if parent.currentOffset != newOffset {
                DispatchQueue.main.async {
                    self.parent.currentOffset = newOffset
                }
            }
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView, let view = hostingController?.view else { return }
            
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let tapPoint = gesture.location(in: view)
                let zoomRect = zoomRectForScale(scale: parent.doubleTapScale, center: tapPoint, scrollView: scrollView)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
        
        private func zoomRectForScale(scale: CGFloat, center: CGPoint, scrollView: UIScrollView) -> CGRect {
            var zoomRect = CGRect.zero
            zoomRect.size.height = scrollView.frame.size.height / scale
            zoomRect.size.width  = scrollView.frame.size.width  / scale
            // The center is in the view's coordinates, which is exactly what we want to center on
            zoomRect.origin.x = center.x - (zoomRect.size.width / 2.0)
            zoomRect.origin.y = center.y - (zoomRect.size.height / 2.0)
            return zoomRect
        }
    }
}
