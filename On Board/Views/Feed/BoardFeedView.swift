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
    var onNewPost: (() -> Void)?
    var isResetting: Bool = false
    var originatingProfileID: UUID? = nil

    // Read from the environment rather than taken as a parameter: the zoom
    // destination lives in ContentView, so every card must register its source in
    // ContentView's namespace. See EnvironmentValues.cardNamespace.
    @Environment(\.cardNamespace) private var cardNamespace
    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rotationIntensity") private var rotationIntensity: Double = 0.6

    @State private var appeared = false
    @State private var rotations: [String: Double] = [:]
    @State private var leftColumn: [FeedItem] = []
    @State private var rightColumn: [FeedItem] = []
    @State private var containerWidth: CGFloat = 0

    private let rowSpacing: CGFloat = 16

    // Outer 16pt padding ×2 + 12pt inter-column gap = 44pt of non-content width.
    private var columnWidth: CGFloat { max(0, (containerWidth - 44) / 2) }

    // MARK: - Body

    var body: some View {
        LazyVStack(spacing: 0) {
            if typeSize.isAccessibilitySize { accessibleStack }
            else { masonryGrid }
        }
        .safeAreaPadding(.bottom, 64)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            guard newWidth != containerWidth else { return }
            containerWidth = newWidth
            recomputeColumns()
        }
        .onAppear {
            seedRotationsIfNeeded()
            recomputeColumnsIfNeeded()
            appeared = true
        }
        .onChange(of: items) { _, _ in
            seedRotationsForNewItems()
            recomputeColumns()
        }
    }

    // MARK: - Grid layouts

    private let rightColumnOffset: CGFloat = 64

    private var masonryGrid: some View {
        // Use cached columns; compute once on first render before onAppear fires.
        var left = leftColumn, right = rightColumn
        if left.isEmpty { (left, right) = distributeToColumns(masonryItems) }
        return HStack(alignment: .top, spacing: 12) {
            LazyVStack(spacing: rowSpacing) {
                ForEach(Array(left.enumerated()), id: \.element.id) { idx, item in
                    masonryCell(item: item, animationIndex: idx * 2, isLeadingColumn: true)
                }
            }
            LazyVStack(spacing: rowSpacing) {
                ForEach(Array(right.enumerated()), id: \.element.id) { idx, item in
                    masonryCell(item: item, animationIndex: idx * 2 + 1, isLeadingColumn: false)
                }
            }
            .padding(.top, rightColumnOffset)
        }
        .padding(.horizontal, 16)
    }

    private var accessibleStack: some View {
        LazyVStack(spacing: rowSpacing) {
            ForEach(Array(masonryItems.enumerated()), id: \.element.id) { idx, item in
                masonryCell(item: item, animationIndex: idx, isLeadingColumn: false)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func masonryCell(item: FeedItem, animationIndex: Int, isLeadingColumn: Bool) -> some View {
        let rot = useRotation ? rotation(for: item) * rotationIntensity : 0
        let flyX: CGFloat = isLeadingColumn ? -320 : 320
        // No .rotationEffect here. A post card's zoom-transition source lives inside
        // GridCard, and a source nested under an ancestor rotation resolves to a
        // rotated quad — which wrecks the interactive (swipe) back transition. GridCard
        // now applies `cardRotation` itself, beneath its own source. Non-post cards,
        // which have no transition source, are rotated in feedItemView instead.
        feedItemView(for: item, cardRotation: rot, isLeadingColumn: isLeadingColumn)
            // Entrance animation
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.94)
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.4).delay(Double(animationIndex) * 0.025),
                value: appeared
            )
            // Reset fly-off — stacks multiplicatively with entrance opacity
            .offset(x: isResetting ? flyX : 0, y: isResetting ? -700 : 0)
            .rotationEffect(
                .degrees(isResetting ? (isLeadingColumn ? -28 : 28) : 0),
                anchor: .bottom
            )
            .opacity(isResetting ? 0 : 1)
            .animation(
                reduceMotion ? .none :
                    .spring(duration: 0.5, bounce: 0.1)
                    .delay(Double(animationIndex) * 0.07),
                value: isResetting
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
        // Base text card height (matches GridCard logic)
        let idealBase = columnWidth * 1.15
        let base: CGFloat = max(180, min(idealBase, 260))
        
        guard columnWidth > 0,
              case .post(let postID, _) = item,
              let post = store.feedPost(id: postID),
              let ratio = post.imageAspectRatio, ratio > 0 else { return base }
        let imageHeight = min(columnWidth / CGFloat(ratio), 300)
        return base + imageHeight - 16 // 16 = peekAmount
    }

    // MARK: - Item rendering

    @ViewBuilder
    private func feedItemView(for item: FeedItem, cardRotation: Double = 0, isLeadingColumn: Bool = false) -> some View {
        switch item {
        case .post(let postID, _):
            // The route is both the link value and the zoom source id, so the source
            // a destination looks up is always the exact card that pushed it.
            let route: BoardRoute = originatingProfileID.map {
                BoardRoute.postFromProfile(postID: postID, profileID: $0)
            } ?? .post(postID)
            NavigationLink(value: route) {
                FeedGridCard(postID: postID, cardNamespace: cardNamespace, transitionID: route, cardRotation: cardRotation, isLeadingColumn: isLeadingColumn, columnWidth: columnWidth)
            }
            .buttonStyle(.plain)
        case .countdown(let week, let isArchived):
            CountdownCard(week: week, isArchived: isArchived, columnWidth: columnWidth)
                .rotationEffect(.degrees(cardRotation))
        case .newPost:
            if let onNewPost {
                Button(action: onNewPost) { NewPostCard(columnWidth: columnWidth) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New post")
                    .rotationEffect(.degrees(cardRotation))
            }
        }
    }

    // MARK: - Rotation

    private var useRotation: Bool {
        rotationIntensity > 0 && !typeSize.isAccessibilitySize && !reduceMotion
    }

    private func rotation(for item: FeedItem) -> Double {
        rotations[item.id, default: 0]
    }

    private func recomputeColumns() {
        (leftColumn, rightColumn) = distributeToColumns(masonryItems)
    }

    private func recomputeColumnsIfNeeded() {
        guard leftColumn.isEmpty else { return }
        recomputeColumns()
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
