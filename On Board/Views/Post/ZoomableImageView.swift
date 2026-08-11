import SwiftUI
import Nuke

// The UIKit half of the image viewer: a full-screen UIScrollView +
// UIImageView owning pinch/pan/double-tap/swipe-dismiss with zero SwiftUI
// involvement per touch. `ImageViewerView` (the SwiftUI half) explains the
// dual-layer architecture and its failure history — read its header before
// changing anything here.
//
// THE 62bfc4a ZOOM-KILLING FEEDBACK LOOP, for whoever touches this next
// (both halves are still structurally possible — do not reintroduce):
//   1. Never infer "the image changed size" from imageView.frame in a
//      zooming scroll view — zoom applies a transform, and frame reports
//      the TRANSFORMED size, so a frame-comparison layout guard resets
//      zoomScale to 1 on every mid-zoom layout pass.
//   2. Never write SwiftUI state per zoom delta — PostDetailView's toolbar
//      observes the viewer, so each write re-rendered the host, re-laid-out
//      this representable, and (via 1) snapped the zoom back. Only the
//      zoomed-in/at-rest threshold CROSSING crosses the bridge.

/// One frame of swipe-to-dismiss state, computed entirely on the UIKit side
/// so every curve (horizontal damping, shrink, backdrop dim) lives in
/// exactly one function. The SwiftUI layer applies these values verbatim —
/// the handoff's pixel-identical guarantee depends on nothing being
/// re-derived on the other side of the bridge.
struct ImageViewerDismissDrag {
    /// Image displacement, horizontal damping already applied.
    let offset: CGSize
    /// Uniform shrink applied to the image as it is pulled down.
    let shrink: CGFloat
    /// Backdrop opacity: 1 at rest, dimming toward the dismiss threshold.
    let backgroundOpacity: Double

    static let rest = ImageViewerDismissDrag(offset: .zero, shrink: 1, backgroundOpacity: 1)
}

struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    let aspectRatio: CGFloat?
    let isPresented: Bool
    /// Fired only when the zoomed-in/at-rest 1.0 threshold is crossed —
    /// never per delta (see the feedback-loop warning above).
    let onZoomChange: (Bool) -> Void
    /// Fired per touch-move of an active swipe-dismiss. The SwiftUI side
    /// uses only `backgroundOpacity` (one leaf view's opacity — cheap).
    let dragChanged: (ImageViewerDismissDrag) -> Void
    /// Fired when a swipe-dismiss crosses the threshold, with the drag
    /// state at the moment of release so the morph layer resumes exactly
    /// where the finger left the image.
    let onDismiss: (ImageViewerDismissDrag) -> Void

    func makeUIView(context: Context) -> ZoomableImageContainerView {
        let view = ZoomableImageContainerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ZoomableImageContainerView, context: Context) {
        uiView.load(url: url, aspectRatio: aspectRatio)
        // Reset happens on the CLOSE edge, once, not every update — resetting
        // unconditionally on every SwiftUI re-render would fight an
        // in-progress gesture.
        if !isPresented, context.coordinator.wasPresented {
            uiView.resetForClose()
        }
        context.coordinator.wasPresented = isPresented
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoomChange: onZoomChange, dragChanged: dragChanged, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject {
        let onZoomChange: (Bool) -> Void
        let dragChanged: (ImageViewerDismissDrag) -> Void
        let onDismiss: (ImageViewerDismissDrag) -> Void
        /// Tracks the presented edge so `updateUIView` resets on close
        /// exactly once, not on every unrelated re-render while closed.
        /// Starts false: the viewer is pre-mounted closed, and the first
        /// update must not run a spurious reset.
        var wasPresented = false
        private var lastReportedZoomedIn = false

        init(
            onZoomChange: @escaping (Bool) -> Void,
            dragChanged: @escaping (ImageViewerDismissDrag) -> Void,
            onDismiss: @escaping (ImageViewerDismissDrag) -> Void
        ) {
            self.onZoomChange = onZoomChange
            self.dragChanged = dragChanged
            self.onDismiss = onDismiss
        }

        func reportScale(_ value: CGFloat) {
            let zoomedIn = value > 1.001
            guard zoomedIn != lastReportedZoomedIn else { return }
            lastReportedZoomedIn = zoomedIn
            onZoomChange(zoomedIn)
        }
    }
}

/// Owns the UIScrollView + UIImageView and every gesture. One job: track
/// touches and paint pixels with zero SwiftUI involvement per frame. Only
/// three things cross back to SwiftUI, each at coarse-grained moments: the
/// zoom threshold crossing, drag state during an unzoomed downward pan, and
/// the dismiss decision itself.
final class ZoomableImageContainerView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var coordinator: ZoomableImageView.Coordinator?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let dismissPan = UIPanGestureRecognizer()
    private var loadedURL: URL?
    private var aspectRatio: CGFloat?
    private var imageTask: ImageTask?

    /// Last container size the image was fitted for. Layout re-fits ONLY
    /// when this or the image changes — never by comparing against
    /// `imageView.frame` (see the header warning).
    private var lastFitSize: CGSize = .zero
    private var imageNeedsFit = false
    /// Whether the dismiss pan currently holds a non-rest transform —
    /// guards the "finger above start point" branch from re-writing the
    /// rest state (and re-rendering SwiftUI) on every touch-move.
    private var isDragDisplaced = false

    private let maxZoomScale: CGFloat = 4.0
    private let doubleTapZoomScale: CGFloat = 2.5
    private let dismissThreshold: CGFloat = 100

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
        // UIImageView defaults this to false; the scroll view's zooming
        // machinery works either way, but explicit is safer for any
        // recognizer that resolves its hit-test to the image itself.
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Swipe-to-dismiss. Three guards keep it from fighting the scroll
        // view's built-in pinch/pan (their absence is what sank 62bfc4a):
        //   - one finger only, so a pinch's two-finger touch pattern never
        //     drives it;
        //   - `gestureRecognizerShouldBegin` refuses it outright while
        //     zoomed in or for non-downward movement, so it never CLAIMS
        //     touches it won't act on (an early-return in the handler still
        //     consumes the gesture);
        //   - simultaneous recognition is granted only to the scroll view's
        //     own pan (inert at rest zoom), NOT its pinch.
        dismissPan.addTarget(self, action: #selector(handleDismissPan(_:)))
        dismissPan.maximumNumberOfTouches = 1
        dismissPan.delegate = self
        // A double-tap with slight downward drift must zoom, not start a
        // dismiss drag (tap recognizers fail fast on real movement, so this
        // adds no perceptible latency to a genuine swipe) — same wiring as
        // Krisiacik/ImageViewer's ItemBaseController.
        dismissPan.require(toFail: doubleTap)
        addGestureRecognizer(dismissPan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // bounds+center, not frame: during a swipe-dismiss the scroll view
        // carries a non-identity transform, and setting `frame` on a
        // transformed view is undefined behavior per UIKit docs.
        if scrollView.bounds.size != bounds.size {
            scrollView.bounds = CGRect(origin: scrollView.bounds.origin, size: bounds.size)
        }
        scrollView.center = CGPoint(x: bounds.midX, y: bounds.midY)

        if bounds.size != lastFitSize || imageNeedsFit {
            lastFitSize = bounds.size
            imageNeedsFit = false
            fitImage()
        }
        centerImage()
    }

    // MARK: - Loading

    func load(url: URL, aspectRatio: CGFloat?) {
        if self.aspectRatio == nil { self.aspectRatio = aspectRatio }
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
            self.imageNeedsFit = true
            self.setNeedsLayout()
        }
        imageNeedsFit = true
        setNeedsLayout()
    }

    /// Sizes the image to aspect-fit the current bounds at 1x, via the same
    /// `CropGeometry` math the crop screens use (two independent fit
    /// implementations could drift by a rounding branch and break the
    /// pixel-identical layer swap). Runs only on a real bounds/image change
    /// (see layoutSubviews), so the zoom reset here can never fire
    /// mid-gesture.
    private func fitImage() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let ratio = aspectRatio ?? 1
        let fitSize = CropGeometry.imageDisplayFrame(
            imageSize: CGSize(width: ratio, height: 1),
            in: bounds.size
        ).size
        scrollView.zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: fitSize)
        scrollView.contentSize = fitSize
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

    // MARK: - Swipe to dismiss (only recognizable at rest zoom — see delegate)

    /// Every dismiss-drag curve in one place: horizontal damping, shrink,
    /// and backdrop dim, all derived from the raw pan translation.
    private func dismissDrag(for translation: CGPoint) -> ImageViewerDismissDrag {
        let progress = min(1, translation.y / dismissThreshold)
        return ImageViewerDismissDrag(
            offset: CGSize(width: translation.x * 0.5, height: translation.y),
            shrink: max(0.8, 1 - translation.y / (dismissThreshold * 4)),
            backgroundOpacity: max(0, 1 - progress * 0.5)
        )
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .changed:
            guard translation.y > 0 else {
                // Dragged back above the start point: restore the rest
                // state once, not on every subsequent move.
                if isDragDisplaced {
                    isDragDisplaced = false
                    scrollView.transform = .identity
                    coordinator?.dragChanged(.rest)
                }
                return
            }
            isDragDisplaced = true
            let drag = dismissDrag(for: translation)
            scrollView.transform = CGAffineTransform(translationX: drag.offset.width, y: drag.offset.height)
                .scaledBy(x: drag.shrink, y: drag.shrink)
            coordinator?.dragChanged(drag)
        case .ended, .cancelled:
            isDragDisplaced = false
            let predicted = gesture.predictedTranslation(in: self, translation: translation)
            if translation.y > dismissThreshold || predicted.y > dismissThreshold {
                // The morph layer takes over the visible motion from the
                // exact drag state passed here; this view is hidden by the
                // same state flip, so its own instant reset in
                // resetForClose() is invisible.
                coordinator?.onDismiss(dismissDrag(for: translation))
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
                coordinator?.dragChanged(.rest)
            }
        default:
            break
        }
    }

    /// Called once when `isPresented` flips to false. This view is hidden
    /// from the first close frame (the morph layer owns the visible
    /// motion), so a plain instant reset is correct — the NEXT open must
    /// start clean. Idempotent.
    func resetForClose() {
        scrollView.setZoomScale(1, animated: false)
        scrollView.transform = .identity
        coordinator?.reportScale(1)
    }

    // MARK: - UIGestureRecognizerDelegate (dismissPan only)

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        // Refuse outright unless at rest zoom AND moving predominantly
        // downward. Refusing here (rather than early-returning in the
        // handler) matters: a recognizer that begins still claims and
        // consumes its touches even if its action is a no-op.
        guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else { return false }
        let velocity = dismissPan.velocity(in: self)
        return velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Coexist ONLY with the scroll view's own pan (inert at rest zoom,
        // which is the only time dismissPan can begin). Deliberately NOT the
        // pinch: granting simultaneity with the pinch let a two-finger
        // gesture drive both zoom and the dismiss transform at once in
        // 62bfc4a.
        otherGestureRecognizer === scrollView.panGestureRecognizer
    }
}

private extension UIPanGestureRecognizer {
    /// UIKit has no `predictedEndTranslation` (a SwiftUI DragGesture-only
    /// API) — this derives the equivalent "will this end up past threshold"
    /// signal: current translation plus velocity extrapolated a short fixed
    /// interval forward.
    func predictedTranslation(in view: UIView?, translation: CGPoint) -> CGPoint {
        let v = velocity(in: view)
        return CGPoint(x: translation.x + v.x * 0.1, y: translation.y + v.y * 0.1)
    }
}
