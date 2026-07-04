//
//  ImageViewerView.swift
//  On Board
//
//  Full-screen image viewer. Supports pinch-to-zoom, drag-to-pan while
//  zoomed, and double-tap to toggle 2×. Dismiss by tapping ×.
//

import SwiftUI
import NukeUI

struct ImageViewerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGPoint = .zero
    private let closeButtonZoomThreshold: CGFloat = 1.1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                ZoomableScrollView(
                    currentScale: $scale,
                    currentOffset: $offset,
                    doubleTapScale: 2.0
                ) {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: proxy.size.width, height: proxy.size.height)
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
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .opacity(scale > closeButtonZoomThreshold ? 0 : 1)
                .allowsHitTesting(scale <= closeButtonZoomThreshold)
                .animation(.easeOut(duration: 0.2), value: scale > closeButtonZoomThreshold)
            }
        }
    }
}
