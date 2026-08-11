//
//  View+Transitions.swift
//  On Board
//

import SwiftUI
import UIKit

extension View {
    /// Applies matchedTransitionSource only when both an id and a namespace are present.
    @ViewBuilder
    func matchedTransitionSource(id: (some Hashable)?, in namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Disables **only** the two-finger pinch-to-dismiss that a
    /// `.navigationTransition(.zoom(...))` destination installs, while leaving the
    /// single-finger interactive edge/drag pop (and the back button) untouched —
    /// so `interactiveDismissDisabled(_:)` still governs the swipe pop as normal.
    ///
    /// There is no public API to selectively disable a zoom transition's
    /// interactive gestures. The transition adds three private recognizers to the
    /// pushed view controller's view:
    ///   • `_UIParallaxTransitionPanGestureRecognizer` — single-finger edge/drag pop
    ///   • `_UISwipeDownGestureRecognizer`             — one-finger swipe-down dismiss
    ///   • `_UITransformGestureRecognizer`             — the **two-finger pinch** ← we kill this
    /// We match the pinch recognizer by its runtime class *name* (a plain string
    /// compare — no private symbols are linked or called) and flip its public
    /// `isEnabled`. If Apple ever renames the class the match simply misses and the
    /// gesture is left at its default, so this fails safe: it can weaken to a no-op
    /// but never crashes and never touches the pop gesture.
    func disableZoomPinchToDismiss() -> some View {
        background(ZoomPinchDisabler().frame(width: 0, height: 0).accessibilityHidden(true))
    }

    /// Applies the zoom navigation transition only when a namespace is present.
    ///
    /// Mirrors the `matchedTransitionSource(id:in:)` overload above, so a single
    /// nil namespace disables *both* ends of the transition at once. That matters:
    /// a destination that keeps `.navigationTransition(.zoom(...))` while its
    /// sources have stopped registering resolves no source rect and collapses the
    /// card toward zero on pop — worse than not having the transition at all.
    ///
    /// This is what `FeatureFlag.zoomTransition` switches: off, every card falls
    /// back to a plain push.
    @ViewBuilder
    func zoomTransition(sourceID: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}

/// Host for `disableZoomPinchToDismiss()`. See that modifier for the rationale.
private struct ZoomPinchDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.disablePinch()
    }

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            disablePinch()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // The zoom recognizers are installed as the push transition runs, which
            // can land a beat after appearance — retry on the next runloop turn too.
            disablePinch()
            DispatchQueue.main.async { [weak self] in self?.disablePinch() }
        }

        func disablePinch() {
            // The transition's recognizers live on the hosting (parent) view
            // controller's view, not on this zero-size helper's own view.
            guard let host = parent?.view else { return }
            for gesture in host.gestureRecognizers ?? []
            where String(describing: type(of: gesture)) == "_UITransformGestureRecognizer" {
                gesture.isEnabled = false
            }
        }
    }
}

struct CardNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace feed cards register their zoom-transition source in.
    ///
    /// In production, `BoardRoute.post` / `.postFromProfile` are resolved by exactly
    /// one `navigationDestination` — ContentView's — which applies
    /// `.navigationTransition(.zoom(sourceID:in:))` against ContentView's `@Namespace`.
    /// A `matchedTransitionSource` registered in any *other* namespace is invisible to
    /// it, so the zoom resolves no source rect and degrades: on pop the card collapses
    /// toward a near-zero frame, then snaps back to its real size.
    ///
    /// `BoardFeedView` is shared by the feed, `ProfileView`, and `ArchivedWeekView`.
    /// The latter two used to pass their own `@Namespace`, silently breaking the zoom.
    /// Threading it through the environment keeps every card registered in the one
    /// namespace the destination actually reads.
    var cardNamespace: Namespace.ID? {
        get { self[CardNamespaceKey.self] }
        set { self[CardNamespaceKey.self] = newValue }
    }
}
