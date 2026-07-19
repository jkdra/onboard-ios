//
//  DoubleTapHeart.swift
//  On Board
//
//  Double-tap-to-like with a heart burst at the tap point. Each tap spawns an
//  independent HeartBurst (own id, own @State) that animates in and removes
//  itself after its lifetime — so rapid taps at different locations show
//  multiple overlapping hearts instead of one shared view teleporting around.
//  The heart shows on *every* double-tap — even when already liked — so the
//  tap always visibly registers; `onLike` only fires when `isLiked()` is false.
//
//  When `onSingleTap` is provided, a plain single tap fires it instead (via
//  ExclusiveGesture giving the double-tap priority). This adds the standard
//  system delay to distinguish single-vs-double tap on that view — expected,
//  same mechanism as double-tap-to-zoom elsewhere on iOS.
//

import SwiftUI

private struct HeartBurst: Identifiable {
    let id = UUID()
    let location: CGPoint
    let rotation: Double
}

private struct HeartBurstView: View {
    let size: CGFloat
    let rotation: Double

    @State private var visible = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(.red)
            .shadow(color: .red.opacity(0.3), radius: size * 0.15)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.3)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { visible = true }
                withAnimation(.easeOut(duration: 0.25).delay(0.45)) { visible = false }
            }
    }
}

private struct DoubleTapHeart: ViewModifier {
    var size: CGFloat
    var isEnabled: Bool
    var isLiked: () -> Bool
    var onLike: () -> Void
    var onSingleTap: (() -> Void)? = nil

    @State private var bursts: [HeartBurst] = []
    /// Single/double-tap disambiguation carries the system's standard delay.
    /// If this view is popped (e.g. NavigationStack back) while that delay is
    /// still pending — or a stray tap lands on it during a pop's transition,
    /// where this app's zoom navigation transition keeps source/destination
    /// both mounted — the resolved tap can otherwise fire after the user has
    /// already moved on, most visibly as onSingleTap's fullScreenCover
    /// reappearing on a screen the user thinks they left. Gate on presence so
    /// a late-resolving gesture is a no-op instead of acting on stale state.
    @State private var isPresentedOnScreen = true

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .overlay {
                ZStack {
                    ForEach(bursts) { burst in
                        HeartBurstView(size: size, rotation: burst.rotation)
                            .position(burst.location)
                    }
                }
                .allowsHitTesting(false)
            }
            .gesture(
                ExclusiveGesture(
                    SpatialTapGesture(count: 2, coordinateSpace: .local),
                    SpatialTapGesture(count: 1, coordinateSpace: .local)
                )
                .onEnded { result in
                    guard isEnabled, isPresentedOnScreen else { return }
                    switch result {
                    case .first(let value):
                        if !isLiked() { onLike() }
                        spawnBurst(at: value.location)
                    case .second:
                        onSingleTap?()
                    }
                }
            )
            .onAppear { isPresentedOnScreen = true }
            .onDisappear { isPresentedOnScreen = false }
    }

    private func spawnBurst(at location: CGPoint) {
        let burst = HeartBurst(location: location, rotation: Double.random(in: -5...5))
        bursts.append(burst)
        let id = burst.id
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            bursts.removeAll { $0.id == id }
        }
    }
}

extension View {
    /// Adds double-tap-to-like with a heart burst at the tap point. `isLiked` reports the
    /// current like state; `onLike` is invoked only when it's not already liked. Pass
    /// `onSingleTap` to also handle a plain single tap on the same view (e.g. opening an
    /// image viewer) — this adds the standard single-vs-double-tap disambiguation delay.
    func doubleTapHeart(
        size: CGFloat,
        isEnabled: Bool,
        isLiked: @escaping () -> Bool,
        onLike: @escaping () -> Void,
        onSingleTap: (() -> Void)? = nil
    ) -> some View {
        modifier(DoubleTapHeart(size: size, isEnabled: isEnabled, isLiked: isLiked, onLike: onLike, onSingleTap: onSingleTap))
    }
}
