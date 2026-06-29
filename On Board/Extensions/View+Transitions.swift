//
//  View+Transitions.swift
//  On Board
//

import SwiftUI

extension View {
    /// Applies matchedTransitionSource only when a namespace is present.
    @ViewBuilder
    func matchedTransitionSource(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
