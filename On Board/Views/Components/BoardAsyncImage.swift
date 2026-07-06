//
//  BoardAsyncImage.swift
//  On Board
//
//  Shared remote image loader for post thumbnails and detail views.
//  Uses NukeUI for reliable caching in Canvas previews and on device.
//  Images are downsampled to their display width (see OnBoardImagePipeline)
//  so a full-resolution camera photo never decodes at full size for a thumbnail.
//

import SwiftUI
import Nuke
import NukeUI

struct BoardAsyncImage: View {
    let url: URL?
    let tone: PostTone
    var contentMode: ContentMode = .fill
    /// Display width in points. When nil, the view measures its own width and
    /// downsamples to that — convenient for callers that don't know it upfront.
    var targetWidth: CGFloat? = nil

    @State private var measuredWidth: CGFloat = 0

    private var resolvedWidth: CGFloat? {
        if let targetWidth, targetWidth > 0 { return targetWidth }
        return measuredWidth > 0 ? measuredWidth : nil
    }

    var body: some View {
        content
            .modifier(MeasureWidth(isActive: targetWidth == nil, width: $measuredWidth))
    }

    @ViewBuilder
    private var content: some View {
        if let url {
            if let width = resolvedWidth {
                LazyImage(request: OnBoardImagePipeline.request(url: url, width: width)) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: contentMode)
                    } else if state.error != nil {
                        failurePlaceholder
                    } else {
                        loadingPlaceholder
                    }
                }
            } else {
                // Width not yet known (self-measuring); hold the layout for one frame.
                loadingPlaceholder
            }
        } else {
            failurePlaceholder
        }
    }

    private var failurePlaceholder: some View {
        tone.color.opacity(0.1)
            .frame(minHeight: 80)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

    private var loadingPlaceholder: some View {
        tone.color.opacity(0.06)
            .frame(minHeight: 100)
            .overlay { ProgressView().tint(tone.color) }
    }
}

/// Reports the view's width back to a binding, only when self-measuring is needed.
private struct MeasureWidth: ViewModifier {
    let isActive: Bool
    @Binding var width: CGFloat

    func body(content: Content) -> some View {
        if isActive {
            content.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                // Lock in the first real measurement rather than tracking width for
                // the view's whole lifetime. A self-measuring image pushed via a
                // `.navigationTransition(.zoom(...))` (e.g. PostDetailView) has its
                // frame animated from a small source card up to full screen, so
                // onGeometryChange fires many times with a different width each
                // frame. That width feeds straight into the image request, and Nuke
                // cancels + restarts the load whenever the request changes — a large
                // image can keep losing that race until the animation ends and then
                // never get requested again, leaving the placeholder spinning
                // forever even though the same URL loads fine elsewhere.
                guard width == 0, newWidth > 0 else { return }
                width = newWidth
            }
        } else {
            content
        }
    }
}
