import SwiftUI
import NukeUI
import Nuke

// TWO LAYERS WITH A HANDOFF (2026-08-07). The viewer is split into:
//
//   - a MORPH layer (this file): a plain SwiftUI fitted image carrying the
//     matchedGeometryEffect — the exact chain from the original SwiftUI
//     implementation, whose card<->viewer morph was the one part everyone
//     agreed looked right. It is visible only while a morph or an
//     interactive dismissal is in flight.
//   - an INTERACTION layer (ZoomableImageView.swift): a full-screen
//     UIScrollView + UIImageView that owns pinch/pan/double-tap/
//     swipe-dismiss with zero SwiftUI involvement per touch — the OS
//     primitive every production photo viewer (NYTPhotoViewer,
//     JXPhotoBrowser, Krisiacik/ImageViewer) is built on. Visible only once
//     the open morph has settled. Both layers aspect-fit the same image
//     into the same bounds, so the swap between them is pixel-identical
//     and invisible.
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

/// Where the viewer is in its presentation lifecycle. The viewer is the
/// single owner of this timing — call sites derive chrome from the phase
/// instead of running their own timers (a duplicated 450ms sleep in
/// PostDetailView once drifted against the viewer's own settle clock).
enum ImageViewerPhase {
    case closed
    /// The open morph is in flight; chrome must stay out of the transaction.
    case morphing
    /// Fully open at rest zoom — the UIKit layer owns the screen and
    /// close chrome (the X button) should be visible.
    case settled
    /// Zoomed past 1.0 — chrome hides until the user returns to rest.
    case zoomedIn

    /// True while the viewer covers the screen (nav back-swipe and the
    /// regular toolbar should stay suppressed).
    var coversScreen: Bool { self == .settled || self == .zoomedIn }
}

/// Single owner of every motion constant the viewer's presentation uses.
/// The settle delay is derived from the morph spring by eyeball (the spring
/// has visually finished by then) — tune them together.
enum ImageViewerMotion {
    /// Card <-> viewer hero morph, used by every open/close call site.
    static let morphSpring: Animation = .spring(response: 0.35, dampingFraction: 1.0)
    /// Swipe-dismiss: the close flip and the glide-home of the dragged
    /// image. Slightly bouncier than the morph so the release keeps the
    /// finger's energy.
    static let dismissSpring: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    /// Chrome fade-in once the viewer settles.
    static let chromeFade: Animation = .easeIn(duration: 0.15)
    /// How long after open before the UIKit layer (and chrome) take over.
    static let settleDelay: Duration = .milliseconds(450)
}

struct ImageViewerView<ID: Hashable>: View {
    let url: URL?
    let namespace: Namespace.ID
    let sourceID: ID
    @Binding var isPresented: Bool
    var aspectRatio: CGFloat? = nil
    /// Read-only lifecycle output for call sites (chrome gating). Callers
    /// still open/close via `isPresented`.
    var phase: Binding<ImageViewerPhase>? = nil

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
    /// two copies of the image. Cleared on every close path before or with
    /// `isPresented`, so `settled` implies `isPresented`.
    @State private var settled = false

    private var resolvedAspectRatio: CGFloat? {
        if let aspect = aspectRatio { return aspect }
        if let size = loadedImageSize { return size.width / size.height }
        return nil
    }

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
        // `.task(id:)` auto-cancels the pending settle when `isPresented`
        // flips mid-morph — no hand-rolled Task bookkeeping.
        .task(id: isPresented) {
            guard isPresented else { return }
            phase?.wrappedValue = .morphing
            try? await Task.sleep(for: ImageViewerMotion.settleDelay)
            guard !Task.isCancelled else { return }
            settled = true
            withAnimation(ImageViewerMotion.chromeFade) {
                phase?.wrappedValue = .settled
            }
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                settled = false
                // Instant and unanimated on purpose — chrome must vanish
                // with the first close frame, mirroring the swipe-close
                // path (the smooth one).
                phase?.wrappedValue = .closed
                // ANIMATED on purpose. This runs outside the caller's
                // withAnimation transaction, so plain assignments here would
                // snap — gliding the transform home alongside the
                // matched-geometry morph is what makes a swipe-dismissal
                // read as one continuous motion.
                withAnimation(ImageViewerMotion.dismissSpring) {
                    scale = 1.0
                    offset = .zero
                    backgroundOpacity = 1.0
                }
            }
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
        .opacity(settled ? 0 : 1)
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
            onZoomChange: { zoomedIn in
                guard settled else { return }
                phase?.wrappedValue = zoomedIn ? .zoomedIn : .settled
            },
            dragChanged: { drag in
                backgroundOpacity = drag.backgroundOpacity
            },
            onDismiss: { drag in
                // Hand the dragged transform to the morph layer BEFORE the
                // close flip: it reappears exactly where the UIKit layer's
                // drag left the image (plain writes, no animation), then
                // the onChange above glides it home inside the morph.
                scale = drag.shrink
                offset = drag.offset
                settled = false
                withAnimation(ImageViewerMotion.dismissSpring) {
                    isPresented = false
                }
            }
        )
        .frame(width: size.width, height: size.height)
        .opacity(settled ? 1 : 0)
        .transaction { $0.animation = nil }
        .allowsHitTesting(settled)
    }
}
