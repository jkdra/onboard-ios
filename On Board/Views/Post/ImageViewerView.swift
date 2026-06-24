//
//  ImageViewerView.swift
//  On Board
//
//  Full-screen image viewer. Supports pinch-to-zoom, drag-to-pan while
//  zoomed, and double-tap to toggle 2×. Dismiss by tapping × or swiping down.
//

import SwiftUI
import NukeUI

struct ImageViewerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var panOffset: CGSize = .zero

    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gesturePan: CGSize = .zero

    private var effectiveScale: CGFloat { scale * gestureScale }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(effectiveScale)
                            .offset(
                                x: panOffset.width + gesturePan.width,
                                y: panOffset.height + gesturePan.height
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .gesture(zoomGesture)
                            .simultaneousGesture(panGesture)
                            .onTapGesture(count: 2) {
                                withAnimation(.smooth(duration: 0.3)) {
                                    if scale > 1 {
                                        scale = 1
                                        panOffset = .zero
                                    } else {
                                        scale = 2
                                    }
                                }
                            }
                    } else if state.error != nil {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        ProgressView()
                            .tint(.white)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                withAnimation(.smooth(duration: 0.25)) {
                    scale = max(1, min(scale * value, 5))
                    if scale == 1 { panOffset = .zero }
                }
            }
    }

    // Pan is only active when zoomed in; at scale 1 a swipe-down can dismiss.
    private var panGesture: some Gesture {
        DragGesture()
            .updating($gesturePan) { value, state, _ in
                guard effectiveScale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard effectiveScale > 1 else { return }
                panOffset = CGSize(
                    width: panOffset.width + value.translation.width,
                    height: panOffset.height + value.translation.height
                )
            }
    }
}
