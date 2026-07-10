//
//  View+Transitions.swift
//  On Board
//

import SwiftUI

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
