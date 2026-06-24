//
//  BoardFeedView.swift
//  On Board
//
//  Two-column masonry feed. All board items — countdown, new-post button, and
//  posts — share the same column grid so the countdown feels like part of the board.
//  Posts are distributed greedily to the shorter column based on estimated
//  card height (200pt base + image card height if the post has an image).
//

import SwiftUI

struct BoardFeedView: View {
    let items: [FeedItem]
    var cardNamespace: Namespace.ID
    var onNewPost: (() -> Void)?

    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rotationEnabled") private var rotationEnabled: Bool = true

    @State private var appeared = false
    @State private var rotations: [String: Double] = [:]

    private let rowSpacing: CGFloat = 16

    // MARK: - Body

    var body: some View {
        LazyVStack(spacing: 0) {
            if typeSize.isAccessibilitySize {
                accessibleStack
            } else {
                masonryGrid
            }
        }
        .safeAreaPadding(.bottom, 64)
        .onAppear {
            seedRotationsIfNeeded()
            appeared = true
        }
        .onChange(of: items.count) { _, _ in
            seedRotationsForNewItems()
        }
    }

    // MARK: - Grid layouts

    private let rightColumnOffset: CGFloat = 64

    private var masonryGrid: some View {
        let (left, right) = distributeToColumns(masonryItems)
        return HStack(alignment: .top, spacing: 12) {
            LazyVStack(spacing: rowSpacing) {
                ForEach(Array(left.enumerated()), id: \.element.id) { idx, item in
                    masonryCell(item: item, animationIndex: idx * 2)
                }
            }
            LazyVStack(spacing: rowSpacing) {
                ForEach(Array(right.enumerated()), id: \.element.id) { idx, item in
                    masonryCell(item: item, animationIndex: idx * 2 + 1)
                }
            }
            .padding(.top, rightColumnOffset)
        }
        .padding(.horizontal, 16)
    }

    private var accessibleStack: some View {
        LazyVStack(spacing: rowSpacing) {
            ForEach(Array(masonryItems.enumerated()), id: \.element.id) { idx, item in
                masonryCell(item: item, animationIndex: idx)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func masonryCell(item: FeedItem, animationIndex: Int) -> some View {
        let rot = useRotation ? rotation(for: item) : 0
        feedItemView(for: item, cardRotation: rot)
            .rotationEffect(.degrees(rot))
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.94)
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.4).delay(Double(animationIndex) * 0.025),
                value: appeared
            )
    }

    // MARK: - Item categorisation

    private var masonryItems: [FeedItem] { items }

    // MARK: - Column distribution

    private func distributeToColumns(_ items: [FeedItem]) -> ([FeedItem], [FeedItem]) {
        var leftH: CGFloat = 0, rightH: CGFloat = 0
        var left: [FeedItem] = [], right: [FeedItem] = []
        for item in items {
            let h = estimatedHeight(for: item)
            if leftH <= rightH {
                left.append(item); leftH += h + rowSpacing
            } else {
                right.append(item); rightH += h + rowSpacing
            }
        }
        return (left, right)
    }

    private func estimatedHeight(for item: FeedItem) -> CGFloat {
        let base: CGFloat = 200
        guard case .post(let postID, _) = item,
              let post = store.feedPost(id: postID),
              let ratio = post.imageAspectRatio, ratio > 0 else { return base }
        let colWidth = (UIScreen.main.bounds.width - 44) / 2
        let imageHeight = min(colWidth / CGFloat(ratio), 300)
        return base + imageHeight - 16 // 16 = peekAmount
    }

    // MARK: - Item rendering

    @ViewBuilder
    private func feedItemView(for item: FeedItem, cardRotation: Double = 0) -> some View {
        switch item {
        case .post(let postID, _):
            NavigationLink(value: BoardRoute.post(postID)) {
                FeedGridCard(postID: postID, cardNamespace: cardNamespace, cardRotation: cardRotation)
            }
            .buttonStyle(.plain)
        case .countdown(let week, let isArchived):
            CountdownCard(week: week, isArchived: isArchived)
        case .newPost:
            if let onNewPost {
                Button(action: onNewPost) { NewPostCard() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New post")
            }
        }
    }

    // MARK: - Rotation

    private var useRotation: Bool {
        rotationEnabled && !typeSize.isAccessibilitySize && !reduceMotion
    }

    private func rotation(for item: FeedItem) -> Double {
        rotations[item.id, default: 0]
    }

    private func seedRotationsIfNeeded() {
        guard rotations.isEmpty else { return }
        seedRotationsForNewItems()
    }

    private func seedRotationsForNewItems() {
        for item in items where rotations[item.id] == nil {
            rotations[item.id] = Double.random(in: -3...3)
        }
    }
}
