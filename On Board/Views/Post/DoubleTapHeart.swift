//
//  DoubleTapHeart.swift
//  On Board
//
//  Double-tap-to-like with a heart burst at the tap point. The heart shows on *every*
//  double-tap — even when already liked — so the tap always visibly registers; `onLike`
//  only fires when `isLiked()` is false. A token guards against a stale 700ms timer
//  hiding the heart mid-sequence during rapid taps.
//

import SwiftUI

private struct DoubleTapHeart: ViewModifier {
    var size: CGFloat
    var isEnabled: Bool
    var isLiked: () -> Bool
    var onLike: () -> Void

    @State private var show = false
    @State private var location: CGPoint = .zero
    @State private var rotation: Double = 0
    @State private var token = 0

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: size))
                    .foregroundStyle(.red)
                    .shadow(color: .red.opacity(0.3), radius: size * 0.15)
                    .opacity(show ? 1 : 0)
                    .scaleEffect(show ? 1 : 0.3)
                    .rotationEffect(.degrees(rotation))
                    .animation(.spring(response: 0.3, dampingFraction: 0.55), value: show)
                    .allowsHitTesting(false)
                    .position(location)
            }
            .gesture(
                SpatialTapGesture(count: 2, coordinateSpace: .local)
                    .onEnded { value in
                        guard isEnabled else { return }
                        location = value.location
                        if !isLiked() { onLike() }
                        rotation = Double.random(in: -5...5)
                        show = true
                        token += 1
                        let current = token
                        Task {
                            try? await Task.sleep(for: .milliseconds(700))
                            if token == current { show = false }
                        }
                    }
            )
    }
}

extension View {
    /// Adds double-tap-to-like with a heart burst at the tap point. `isLiked` reports the
    /// current like state; `onLike` is invoked only when it's not already liked.
    func doubleTapHeart(
        size: CGFloat,
        isEnabled: Bool,
        isLiked: @escaping () -> Bool,
        onLike: @escaping () -> Void
    ) -> some View {
        modifier(DoubleTapHeart(size: size, isEnabled: isEnabled, isLiked: isLiked, onLike: onLike))
    }
}
