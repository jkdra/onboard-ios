//
//  BoardFeedView.swift
//  On Board
//
//  Shared lazy grid for the active week and archived week feeds.
//

import SwiftUI

struct BoardFeedView: View {
    let items: [FeedItem]
    var cardNamespace: Namespace.ID
    var onNewPost: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rotationEnabled") private var rotationEnabled: Bool = true

    @State private var appeared = false
    @State private var rotations: [String: Double] = [:]

    private let columnOffset: CGFloat = 64
    private let rowSpacing: CGFloat = 16
    private let accessibleColumns = [GridItem(.flexible(), spacing: 24)]
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var useRotation: Bool {
        rotationEnabled && !typeSize.isAccessibilitySize && !reduceMotion
    }

    var body: some View {
        LazyVGrid(
            columns: typeSize.isAccessibilitySize ? accessibleColumns : columns,
            spacing: rowSpacing
        ) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                feedItemView(for: item)
                    .rotationEffect(.degrees(useRotation ? rotation(for: item) : 0))
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.94)
                    .animation(
                        reduceMotion ? .none : .smooth(duration: 0.4).delay(Double(index) * 0.025),
                        value: appeared
                    )
                    .offset(y: index.isMultiple(of: 2) ? 0 : (typeSize.isAccessibilitySize ? 0 : columnOffset))
            }
        }
        .safeAreaPadding(.horizontal)
        .safeAreaPadding(.bottom, typeSize.isAccessibilitySize ? 0 : 64)
        .onAppear {
            seedRotationsIfNeeded()
            appeared = true
        }
        .onChange(of: items.count) { _, _ in
            seedRotationsForNewItems()
        }
    }

    @ViewBuilder
    private func feedItemView(for item: FeedItem) -> some View {
        switch item {
        case .post(let postID, _):
            NavigationLink(value: BoardRoute.post(postID)) {
                FeedGridCard(postID: postID)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: postID, in: cardNamespace)
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
