//
//  FeedSkeletonView.swift
//  On Board
//
//  Cold-load placeholder for the board feed: ghost cards in the real masonry
//  geometry — two columns, right column offset, alternating heights, slight
//  rotations — so the loading state already looks like On Board and the real
//  cards replace it without reflow. Shown only when there's no cached feed.
//

import SwiftUI

struct FeedSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Mirrors BoardFeedView's card silhouette: 18pt radius, masonry heights.
    private let leftHeights: [CGFloat] = [210, 260, 180]
    private let rightHeights: [CGFloat] = [240, 190, 230]
    private let rotations: [Double] = [-1.6, 1.2, -0.8, 1.8, -1.2, 0.9]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(heights: leftHeights, rotationOffset: 0)
            column(heights: rightHeights, rotationOffset: 3)
                .padding(.top, 64)
        }
        .padding(.horizontal, 16)
        .accessibilityElement()
        .accessibilityLabel("Loading your board")
    }

    private func column(heights: [CGFloat], rotationOffset: Int) -> some View {
        VStack(spacing: 16) {
            ForEach(Array(heights.enumerated()), id: \.offset) { idx, height in
                SkeletonShape(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(height: height)
                    .rotationEffect(.degrees(reduceMotion ? 0 : rotations[(idx + rotationOffset) % rotations.count]))
            }
        }
    }
}

#Preview {
    ScrollView {
        FeedSkeletonView()
    }
}
