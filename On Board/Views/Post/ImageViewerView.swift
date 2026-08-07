import SwiftUI
import NukeUI
import Nuke

// TWO LAYERS WITH A HANDOFF (2026-08-07). The viewer is split into:
//
//   - a MORPH layer: a plain SwiftUI fitted image carrying the
//     matchedGeometryEffect — the exact chain from the original SwiftUI
//     implementation, whose card<->viewer morph was the one part everyone
//     agreed looked right. It is visible only while a morph or an
//     interactive dismissal is in flight.
//   - an INTERACTION layer: a full-screen UIScrollView + UIImageView
//     (UIViewRepresentable) that owns pinch/pan/double-tap/swipe-dismiss
//     with zero SwiftUI involvement per touch — the OS primitive every
//     production photo viewer (NYTPhotoViewer, JXPhotoBrowser,
//     Krisiacik/ImageViewer) is built on. Visible only once the open morph
//     has settled. Both layers aspect-fit the same image into the same
//     bounds, so the swap between them is pixel-identical and invisible.
//
// WHY NOT ONE LAYER? Both single-layer variants shipped and failed:
//   - All-SwiftUI (through 696819d): every pinch/drag delta re-ran a
//     SwiftUI diff+layout through the matchedGeometryEffect chain,
//     competing with PostDetailView's comments/composer for the same
//     8.33ms 120Hz frame budget — the original on-device stutter.
//   - matchedGeometryEffect directly on the representable (62bfc4a and the
//     first corrected rebuild): SwiftUI animates a UIView's frame by
//     SCALING ITS LAYER, not re-laying it out per frame — so the morph
//     squeezed the final full-screen letterboxed composition into the card
//     rect instead of growing the image out of the card. The morph must
//     live on a native SwiftUI image whose matched rect IS the fitted
//     image rect.
//
// THE 62bfc4a ZOOM-KILLING FEEDBACK LOOP, for whoever touches this next
// (both halves are still structurally possible — do not reintroduce):
//   1. Never infer "the image changed size" from imageView.frame in a
//      zooming scroll view — zoom applies a transform, and frame reports
//      the TRANSFORMED size, so a frame-comparison layout guard resets
//      zoomScale to 1 on every mid-zoom layout pass.
//   2. Never write a SwiftUI binding per zoom delta — PostDetailView's
//      toolbar reads the bound scale, so each write re-rendered the host,
//      re-laid-out the representable, and (via 1) snapped the zoom back.
//      Only the 1.0 chrome-threshold CROSSING is reported.

struct ImageViewerView<ID: Hashable>: View {
    let url: URL?
    let namespace: Namespace.ID
    let sourceID: ID
    @Binding var isPresented: Bool
    var aspectRatio: CGFloat? = nil
    var currentScale: Binding<CGFloat>? = nil

    // Morph-layer transform state — meaningful only while the morph layer
    // is showing (open/close morphs and the tail of a swipe-dismiss).
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var backgroundOpacity: Double = 1.0
    @State private var loadedImageSize: CGSize?

    /// True once the open morph has finished and the UIKit layer owns the
    /// screen. Every write is deliberately plain (never inside
    /// `withAnimation`) so the layer swap is an instant, invisible flip
    /// between two pixel-identical frames — animating it would crossfade
    /// two copies of the image.
    @State private var settled = false
    @State private var settleTask: Task<Void, Never>?
    @State private var internalScale: CGFloat = 1.0

    private var resolvedAspectRatio: CGFloat? {
        if let aspect = aspectRatio { return aspect }
        if let size = loadedImageSize { return size.width / size.height }
        return nil
    }

    /// How long after `isPresented` flips true before the UIKit layer takes
    /// over. Matches PostDetailView's deferred-chrome delay: the 0.35s
    /// morph spring has visually finished by then.
    private var settleDelay: Duration { .milliseconds(450) }

    // PRE-MOUNTED, on purpose (2026-08-07). Every native-feeling viewer
    // animates a layer that already exists; the open morph must be pure
    // geometry + opacity on committed layers. Both layers live in the
    // hierarchy whenever the post has an image (hidden, hit-testing off);
    // `isPresented` only flips opacity and the matched-geometry source
    // handoff.
    var body: some View {
        ZStack {
            if let url {
                Color.black
                    .ignoresSafeArea()
                    .opacity(isPresented ? backgroundOpacity : 0)

                GeometryReader { proxy in
                    ZStack {
                        morphLayer(url: url, in: proxy.size)
                        interactionLayer(url: url, in: proxy.size)
                    }
                }
            }
        }
        // CRITICAL with the pre-mounted structure: the hidden layers must be
        // transparent to touches or an invisible full-screen view eats every
        // tap and scroll on the post beneath it.
        .allowsHitTesting(isPresented)
        .onChange(of: isPresented) { _, presented in
            if presented {
                settleTask?.cancel()
                settleTask = Task {
                    try? await Task.sleep(for: settleDelay)
                    guard !Task.isCancelled, isPresented else { return }
                    settled = true
                }
            } else {
                settleTask?.cancel()
                settled = false
                // ANIMATED on purpose. This runs outside the caller's
                // withAnimation transaction, so plain assignments here would
                // snap — gliding the transform home alongside the
                // matched-geometry morph is what makes a swipe-dismissal
                // read as one continuous motion.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    scale = 1.0
                    offset = .zero
                    backgroundOpacity = 1.0
                }
                currentScale?.wrappedValue = 1.0
            }
        }
        .onChange(of: internalScale) { _, newScale in
            currentScale?.wrappedValue = newScale
        }
    }

    /// The matched-geometry morph layer — native SwiftUI, sized to the
    /// FITTED IMAGE RECT (not the screen). The matched rect must be the
    /// image itself: matching the full-screen rect makes the morph
    /// interpolate the letterboxed composition into the card frame.
    @ViewBuilder
    private func morphLayer(url: URL, in size: CGSize) -> some View {
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
        .frame(maxWidth: size.width, maxHeight: size.height)
        // While the UIKit layer owns the screen this layer is hidden — via
        // its own modifier, stripped of animation, so the hide/show is an
        // instant swap even when the triggering state change rides an
        // animated transaction (e.g. the close flip). The animated
        // `isPresented` fade below stays a separate modifier: opacities
        // multiply, and each animates independently.
        .opacity(settled && isPresented ? 0 : 1)
        .transaction { $0.animation = nil }
        // Source only while open — the card's anchor holds the other half
        // of the handoff (`isSource: !viewerOpen`), so steady state always
        // has exactly one source and the open/close morphs interpolate
        // between the two without any view being inserted or removed.
        .matchedGeometryEffect(id: sourceID, in: namespace, isSource: isPresented)
        .position(x: size.width / 2, y: size.height / 2)
        .scaleEffect(scale)
        .offset(offset)
        .opacity(isPresented ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// The full-screen UIKit zoom surface. No matchedGeometryEffect — its
    /// frame never animates, so it is never subject to the representable
    /// layer-scaling artifact, and its fit layout runs exactly once per
    /// size/image change.
    @ViewBuilder
    private func interactionLayer(url: URL, in size: CGSize) -> some View {
        ZoomableImageView(
            url: url,
            aspectRatio: aspectRatio,
            isPresented: isPresented,
            scale: $internalScale,
            dragProgress: { progress in
                // 0 at rest, 1 at the dismiss threshold — same curve the
                // original SwiftUI drag handler used. Drives one leaf
                // view's opacity; cheap by construction.
                backgroundOpacity = max(0, 1 - progress * 0.5)
            },
            onDismiss: { translation, shrink in
                // Hand the dragged transform to the morph layer BEFORE the
                // close flip: it reappears exactly where the UIKit layer's
                // drag left the image (plain writes, no animation), then
                // the onChange above glides it home inside the morph.
                scale = shrink
                offset = CGSize(width: translation.x * 0.5, height: translation.y)
                settled = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isPresented = false
                }
            }
        )
        .frame(width: size.width, height: size.height)
        .opacity(settled && isPresented ? 1 : 0)
        .transaction { $0.animation = nil }
        .allowsHitTesting(isPresented && settled)
    }
}

// MARK: - UIScrollView-backed zoom surface

private struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    let aspectRatio: CGFloat?
    let isPresented: Bool
    @Binding var scale: CGFloat
    let dragProgress: (Double) -> Void
    /// Called when a swipe-dismiss crosses the threshold, with the final
    /// pan translation and the shrink scale applied at that moment.
    let onDismiss: (CGPoint, CGFloat) -> Void

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
        let onDismiss: (CGPoint, CGFloat) -> Void
        /// Tracks the presented edge so `updateUIView` resets on close
        /// exactly once, not on every unrelated re-render while closed.
        var wasPresented = true
        private var lastReportedZoomedIn = false

        init(
            scale: Binding<CGFloat>,
            dragProgress: @escaping (Double) -> Void,
            onDismiss: @escaping (CGPoint, CGFloat) -> Void
        ) {
            self.scaleBinding = scale
            self.dragProgress = dragProgress
            self.onDismiss = onDismiss
        }

        /// The binding's only consumers gate nav chrome on `scale <= 1.0` —
        /// so only threshold CROSSINGS are reported. Reporting every zoom
        /// delta would re-render PostDetailView (whose toolbar reads the
        /// bound state) on every touch-move: exactly the per-frame SwiftUI
        /// involvement this architecture exists to remove, and (via the
        /// re-layout it triggers) the loop that broke zoom outright in
        /// 62bfc4a.
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
    /// `imageView.frame`, which reflects the zoom transform and made
    /// 62bfc4a's guard reset zoom on every mid-gesture layout pass.
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
            scrollView.transform = CGAffineTransform(translationX: translation.x * 0.5, y: translation.y)
                .scaledBy(x: shrink(for: translation.y), y: shrink(for: translation.y))
            coordinator?.dragProgress(progress)
        case .ended, .cancelled:
            let predicted = gesture.predictedTranslation(in: self, translation: translation)
            if translation.y > dismissThreshold || predicted.y > dismissThreshold {
                // The morph layer takes over the visible motion from the
                // exact dragged transform (passed here); this view is
                // hidden by the same state flip, so its own instant reset
                // in resetForClose() is invisible.
                coordinator?.onDismiss(translation, shrink(for: translation.y))
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

    /// The same shrink curve the original SwiftUI drag handler applied —
    /// shared between the live drag and the dismiss handoff so the morph
    /// layer picks up exactly the transform the finger left.
    private func shrink(for dragY: CGFloat) -> CGFloat {
        max(0.8, 1 - dragY / (dismissThreshold * 4))
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
