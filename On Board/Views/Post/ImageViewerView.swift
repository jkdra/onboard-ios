import SwiftUI
import Nuke

// REBUILT ON UIScrollView (2026-08-08, corrected 2026-08-07 after the first
// attempt regressed). The previous SwiftUI version drove pinch/pan/double-tap
// entirely through @State (scale, offset) recomputed on every
// MagnifyGesture/DragGesture delta — every touch-move forced a SwiftUI
// diff+layout pass through this view's whole chain (matchedGeometryEffect +
// scaleEffect + offset), competing with PostDetailView's other content
// (comments, composer, reaction bar) for the SAME transaction. On a 120Hz
// display the frame budget is 8.33ms; three narrower fixes (ProMotion plist
// key, pre-mounting, deferred nav chrome) each removed one secondary cost but
// the interactive gesture loop itself still went through SwiftUI per frame.
//
// Every production photo viewer (NYTPhotoViewer, JTSImageViewController,
// SimpleImageViewer) is built the same way: UIScrollView for zoom/pan —
// hardware-accelerated, zero SwiftUI involvement per touch — with a thin
// custom pan only for swipe-to-dismiss. The outer matchedGeometryEffect morph
// (card <-> viewer) is unchanged.
//
// WHY THE FIRST UIScrollView ATTEMPT (62bfc4a) BROKE ZOOM ENTIRELY — do not
// reintroduce either half of this loop:
//   1. Its layout guard compared `imageView.frame.size` against the fitted
//      size — but UIScrollView zooming APPLIES A TRANSFORM to imageView, and
//      `frame` reports the transformed size. Any layout pass mid-zoom
//      therefore "detected a size change" and reset zoomScale to 1.
//   2. Layout passes were guaranteed mid-zoom, because every zoom delta was
//      reported through the SwiftUI `scale` binding → PostDetailView's
//      toolbar (which reads it) re-rendered → the representable re-laid out.
// Net effect: every pinch delta snapped back to 1x and double-tap's animated
// zoom was cancelled on its first delegate callback. The fix is both-ended:
// layout re-fits ONLY when bounds or the image actually change (tracked
// explicitly, never inferred from the transformed frame), and the scale
// binding is only written when crossing the 1.0 chrome-visibility threshold
// (its only consumer), so a pinch never re-renders SwiftUI at all.

struct ImageViewerView<ID: Hashable>: View {
    let url: URL?
    let namespace: Namespace.ID
    let sourceID: ID
    @Binding var isPresented: Bool
    var aspectRatio: CGFloat? = nil
    var currentScale: Binding<CGFloat>? = nil

    // Background dimming during an interactive swipe-to-dismiss. Left as
    // plain SwiftUI @State deliberately: it drives exactly one leaf view's
    // `.opacity`, which is cheap regardless of where the drag math lives.
    @State private var backgroundOpacity: Double = 1.0
    @State private var internalScale: CGFloat = 1.0

    // PRE-MOUNTED, on purpose (2026-08-07, kept through the rebuild). Every
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
        // in-progress gesture.
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
        private var lastReportedZoomedIn = false

        init(scale: Binding<CGFloat>, dragProgress: @escaping (Double) -> Void, onDismiss: @escaping () -> Void) {
            self.scaleBinding = scale
            self.dragProgress = dragProgress
            self.onDismiss = onDismiss
        }

        /// The binding's only consumers gate nav chrome on `scale <= 1.0` —
        /// so only threshold CROSSINGS are reported. Reporting every zoom
        /// delta would re-render PostDetailView (whose toolbar reads the
        /// bound state) on every touch-move: exactly the per-frame SwiftUI
        /// involvement this rebuild exists to remove, and (via the re-layout
        /// it triggers) the loop that broke zoom outright in 62bfc4a.
        func reportScale(_ value: CGFloat) {
            let zoomedIn = value > 1.001
            guard zoomedIn != lastReportedZoomedIn else { return }
            lastReportedZoomedIn = zoomedIn
            scaleBinding.wrappedValue = zoomedIn ? value : 1.0
        }
    }
}

/// Owns the UIScrollView + UIImageView and every gesture. One job: track
/// touches and paint pixels with zero SwiftUI involvement per frame. Only
/// three things cross back to SwiftUI, each at coarse-grained moments: the
/// zoomed-in/at-rest threshold crossing (for the toolbar's Close-button
/// gate), live drag progress during an unzoomed downward pan (for the
/// backdrop dim), and the dismiss decision itself.
private final class ZoomableImageContainerView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var coordinator: ZoomableImageView.Coordinator?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let dismissPan = UIPanGestureRecognizer()
    private var loadedURL: URL?
    private var aspectRatio: CGFloat?
    private var imageTask: ImageTask?

    /// Last container size the image was fitted for. Layout re-fits ONLY
    /// when this or the image changes — never by comparing against
    /// `imageView.frame`, which reflects the zoom transform and made the
    /// original guard reset zoom on every mid-gesture layout pass.
    private var lastFitSize: CGSize = .zero
    private var imageNeedsFit = false

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

    /// Sizes the image to aspect-fit the current bounds at 1x. Runs only on
    /// a real bounds/image change (see layoutSubviews), so the zoom reset
    /// here can never fire mid-gesture.
    private func fitImage() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let ratio = aspectRatio ?? (imageView.image.map { $0.size.width / $0.size.height }) ?? 1
        var fitSize = bounds.size
        if ratio > bounds.width / bounds.height {
            fitSize = CGSize(width: bounds.width, height: bounds.width / ratio)
        } else {
            fitSize = CGSize(width: bounds.height * ratio, height: bounds.height)
        }
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

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .changed:
            guard translation.y > 0 else {
                // Dragged back above the start point: rest state, no dim.
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
            let predicted = gesture.predictedTranslation(in: self, translation: translation)
            if translation.y > dismissThreshold || predicted.y > dismissThreshold {
                // Do NOT snap the transform to identity here — the image
                // must glide home from its dragged position ALONGSIDE the
                // matched-geometry morph or the release visibly jumps
                // (62bfc4a snapped, and it read as a glitch).
                // `resetForClose()` (via updateUIView on the close edge)
                // animates it home with the same spring as the morph.
                coordinator?.onDismiss()
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

    /// Called once when `isPresented` flips to false. Glides any in-flight
    /// dismiss transform home with the same spring as the close morph (the
    /// two compose into one continuous motion), and zeroes zoom so the next
    /// open starts clean. Idempotent.
    func resetForClose() {
        scrollView.setZoomScale(1, animated: false)
        if scrollView.transform != .identity {
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0
            ) {
                self.scrollView.transform = .identity
            }
        }
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
