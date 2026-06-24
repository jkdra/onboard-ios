//
//  BoardAsyncImage.swift
//  On Board
//
//  Shared remote image loader for post thumbnails and detail views.
//  Uses NukeUI for reliable caching in Canvas previews and on device.
//

import SwiftUI
import NukeUI

struct BoardAsyncImage: View {
    let url: URL?
    let tone: PostTone
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else if state.error != nil {
                    failurePlaceholder
                } else {
                    loadingPlaceholder
                }
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
