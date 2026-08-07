import SwiftUI
import Nuke

// REBUILT ON UIScrollView (2026-08-08). The previous version drove
// pinch/pan/double-tap/dismiss entirely through SwiftUI @State (scale,
// offset) recomputed on every MagnifyGesture/DragGesture delta — every
// touch-move forced a SwiftUI diff+layout pass through this view's whole
// chain (matchedGeometryEffect + scaleEffect + offset), competing with
// PostDetailView's other content (comments, composer, reaction bar) for
// the SAME transaction. On a 120Hz display the frame budget is 8.33ms;
// three narrower fixes (ProMotion plist key, pre-mounting, deferred nav
// chrome) each removed one secondary cost but the interactive gesture loop
// itself was still going through SwiftUI on every frame, and it still
// stuttered on-device.
//
// Every production photo viewer researched (NYTPhotoViewer,
// JTSImageViewController, SimpleImageViewer) is built the same way:
// UIScrollView for zoom/pan — hardware-accelerated, zero-diff, the actual
// OS primitive photo apps are built on — with a thin custom layer only for
// the swipe-to-dismiss gesture UIScrollView doesn't provide. That's what
// this is now. The outer matchedGeometryEffect morph (card <-> viewer) is
// UNCHANGED — it already worked; only the INTERACTIVE surface moved off
// SwiftUI's gesture/state loop.

struct ImageViewerView<ID: Hashable>: View {
    let url: URL?
    let namespace: Namespace.ID
    let sourceID: ID
    @Binding var isPresented: Bool
    var aspectRatio: CGFloat? = nil
    var currentScale: Binding<CGFloat>? = nil

    // Background dimming during an interactive swipe-to-dismiss. Left as
    // plain SwiftUI @State deliberately: it drives exactly one leaf view's
    // `.opacity`, which is cheap regardless of where the drag math lives —
    // the expensive part was never dimming the backdrop, it was recomputing
    // the IMAGE's transform every touch-move through SwiftUI's diff loop.
    @State private var backgroundOpacity: Double = 1.0
    @State private var internalScale: CGFloat = 1.0

    // PRE-MOUNTED, on purpose (2026-08-07, kept 2026-08-08). Every
    // native-feeling viewer animates a layer that already exists; the open
    // morph must be pure geometry + opacity on committed layers. The image
    // lives in the hierarchy whenever the post has one (hidden, hit-testing
    // off); `isPresented` only flips opacity and the matched-geometry
    // source handoff.
    var body: some View {
        ZStack {
            if let url {
                Color.black
                    .ignoresSafeArea()
                    .opacity(isPresented ? backgroundOpacity : 0)

                GeometryReader { proxy in
                    ZoomableImageView(
                        url: url,
                        aspectRatio: aspectRatio,
                        isPresented: isPresented,
                        scale: $internalScale,
                        dragProgress: { progress in
                            // 0 at rest, 1 at the dismiss threshold — same
                            // curve the old SwiftUI drag handler used.
                            backgroundOpacity = max(0, 1 - progress * 0.5)
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    // Source only while open — the card's anchor holds the
                    // other half of the handoff (`isSource: !viewerOpen`),
                    // so steady state always has exactly one source and the
                    // open/close morphs interpolate between the two without
                    // any view being inserted or removed.
                    .matchedGeometryEffect(id: sourceID, in: namespace, isSource: isPresented)
                    .opacity(isPresented ? 1 : 0)
                }
            }
        }
        // CRITICAL with the pre-mounted structure: the hidden layers must be
        // transparent to touches or an invisible full-screen view eats every
        // tap and scroll on the post beneath it.
        .allowsHitTesting(isPresented)
        .onChange(of: isPresented) { _, presented in
            if !presented {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    backgroundOpacity = 1.0
                }
            }
        }
        .onChange(of: internalScale) { _, newScale in
            currentScale?.wrappedValue = newScale
        }
    }
}

// MARK: - UIScrollView-backed zoom surface

private struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    let aspectRatio: CGFloat?
    let isPresented: Bool
    @Binding var scale: CGFloat
    let dragProgress: (Double) -> Void
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> ZoomableImageContainerView {
        let view = ZoomableImageContainerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ZoomableImageContainerView, context: Context) {
        uiView.load(url: url, aspectRatio: aspectRatio)
        // Reset happens on the CLOSE edge, once, not every update — resetting
        // unconditionally on every SwiftUI re-render would fight an
        // in-progress interactive gesture (e.g. `imageViewerScale` feeding
        // back into a toolbar re-render mid-pinch).
        if !isPresented, context.coordinator.wasPresented {
            uiView.resetForClose()
        }
        context.coordinator.wasPresented = isPresented
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scale: $scale, dragProgress: dragProgress, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject {
        let scaleBinding: Binding<CGFloat>
        let dragProgress: (Double) -> Void
        let onDismiss: () -> Void
        /// Tracks the presented edge so `updateUIView` resets on close
        /// exactly once, not on every unrelated re-render while closed.
        var wasPresented = true

        init(scale: Binding<CGFloat>, dragProgress: @escaping (Double) -> Void, onDismiss: @escaping () -> Void) {
            self.scaleBinding = scale
            self.dragProgress = dragProgress
            self.onDismiss = onDismiss
        }

        func reportScale(_ value: CGFloat) {
            // UIKit delegate callbacks aren't necessarily main-actor-checked
            // by the compiler the way SwiftUI state is; scrollView delegate
            // methods always land on main in practice, but this keeps the
            // binding write unambiguous.
            scaleBinding.wrappedValue = value
        }
    }
}

/// Owns the UIScrollView + UIImageView and every gesture. One job: track
/// touches and paint pixels with zero SwiftUI involvement per frame. Only
/// three things cross back to SwiftUI, and only at coarse-grained moments:
/// the current zoom scale (for the toolbar's Close-button visibility gate),
/// live drag progress during an unzoomed downward pan (for the backdrop
/// dim), and the dismiss decision itself.
private final class ZoomableImageContainerView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var coordinator: ZoomableImageView.Coordinator?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var loadedURL: URL?
    private var aspectRatio: CGFloat?
    private var imageTask: ImageTask?

    private let maxZoomScale: CGFloat = 4.0
    private let doubleTapZoomScale: CGFloat = 2.5
    private let dismissThreshold: CGFloat = 100

    private var dismissPanStartCenter: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Runs ALONGSIDE the scroll view's own pan recognizer (delegate
        // below returns true for simultaneous recognition) — it only ever
        // acts when zoomScale is at minimum, which is exactly when the
        // scroll view's own pan has nothing to scroll anyway.
        let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        addGestureRecognizer(dismissPan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        layoutImageIfNeeded()
    }

    // MARK: - Loading

    func load(url: URL, aspectRatio: CGFloat?) {
        self.aspectRatio = aspectRatio
        guard url != loadedURL else { return }
        loadedURL = url
        imageTask?.cancel()
        // Unprocessed, full-resolution request — PostDetailView already warms
        // this exact request while the post is on screen, so it's typically
        // an instant cache hit by the time the viewer opens.
        imageTask = ImagePipeline.shared.loadImage(with: url) { [weak self] result in
            guard let self, let image = try? result.get().image else { return }
            self.imageView.image = image
            self.aspectRatio = image.size.width / image.size.height
            self.setNeedsLayout()
        }
        setNeedsLayout()
    }

    private func layoutImageIfNeeded() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let ratio = aspectRatio ?? (imageView.image.map { $0.size.width / $0.size.height }) ?? 1
        var fitSize = bounds.size
        if ratio > bounds.width / bounds.height {
            fitSize = CGSize(width: bounds.width, height: bounds.width / ratio)
        } else {
            fitSize = CGSize(width: bounds.height * ratio, height: bounds.height)
        }
        // Re-deriving from scratch on every layout pass is cheap (a handful
        // of CGFloat ops) and avoids tracking whether a resize invalidated
        // a cached frame — this only runs on bounds/image changes, never on
        // a gesture frame.
        if imageView.frame.size != fitSize {
            imageView.frame = CGRect(origin: .zero, size: fitSize)
            scrollView.contentSize = fitSize
            scrollView.zoomScale = 1
        }
        centerImage()
    }

    private func centerImage() {
        let boundsSize = scrollView.bounds.size
        var frame = imageView.frame
        frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
        imageView.frame = frame
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        coordinator?.reportScale(scrollView.zoomScale)
    }

    // MARK: - Double tap

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let targetSize = CGSize(
            width: scrollView.bounds.width / doubleTapZoomScale,
            height: scrollView.bounds.height / doubleTapZoomScale
        )
        let zoomRect = CGRect(
            x: point.x - targetSize.width / 2,
            y: point.y - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        scrollView.zoom(to: zoomRect, animated: true)
    }

    // MARK: - Swipe to dismiss (only meaningful at rest zoom)

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
            // Zoomed in: this gesture has no job, and the scroll view's own
            // pan recognizer owns panning the content.
            dismissPanStartCenter = nil
            return
        }
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began:
            dismissPanStartCenter = scrollView.center
        case .changed:
            guard translation.y > 0 else {
                // Upward drag with nothing to scroll to: ignore rather than
                // fight — this mirrors the old "only dragAmount > 0 counts"
                // guard.
                scrollView.transform = .identity
                coordinator?.dragProgress(0)
                return
            }
            let progress = min(1, translation.y / dismissThreshold)
            let shrink = max(0.8, 1 - translation.y / (dismissThreshold * 4))
            scrollView.transform = CGAffineTransform(translationX: translation.x * 0.5, y: translation.y)
                .scaledBy(x: shrink, y: shrink)
            coordinator?.dragProgress(progress)
        case .ended, .cancelled:
            let predicted = gesture.predictedVelocity(in: self, translation: translation)
            let crossedThreshold = translation.y > dismissThreshold || predicted.y > dismissThreshold
            if crossedThreshold {
                coordinator?.onDismiss()
                // The outer matchedGeometryEffect morph takes over the
                // visible motion the instant `isPresented` flips; reset
                // this view's own transform without animation so it isn't
                // still mid-shrink underneath that morph on next present.
                scrollView.transform = .identity
                coordinator?.dragProgress(0)
            } else {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0,
                    options: [.allowUserInteraction]
                ) {
                    self.scrollView.transform = .identity
                }
                coordinator?.dragProgress(0)
            }
        default:
            break
        }
    }

    /// Called once when `isPresented` flips to false — zeroes zoom and any
    /// in-flight dismiss transform so the NEXT open starts clean. Idempotent.
    func resetForClose() {
        scrollView.setZoomScale(1, animated: false)
        scrollView.transform = .identity
        coordinator?.reportScale(1)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Let the dismiss-pan and the scroll view's own pan coexist — the
        // dismiss-pan is a no-op whenever zoomed in (see handleDismissPan),
        // so there's nothing to arbitrate in that case, and at rest zoom
        // the scroll view's pan has no content to scroll anyway.
        true
    }
}

private extension UIPanGestureRecognizer {
    /// `predictedVelocity` doesn't exist on UIPanGestureRecognizer — this
    /// derives an equivalent "will this end up past threshold" signal from
    /// raw velocity, matching the SwiftUI predecessor's use of
    /// `predictedEndTranslation` (a DragGesture-only API with no UIKit
    /// equivalent): current translation plus velocity extrapolated a short
    /// fixed interval forward.
    func predictedVelocity(in view: UIView?, translation: CGPoint) -> CGPoint {
        let v = velocity(in: view)
        return CGPoint(x: translation.x + v.x * 0.1, y: translation.y + v.y * 0.1)
    }
}
