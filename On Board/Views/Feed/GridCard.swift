//
//  GridCard.swift
//  On Board
//

import SwiftUI

struct GridCard: View {
    let post: Post
    var userReaction: Reaction?
    var cardNamespace: Namespace.ID? = nil
    var cardRotation: Double = 0

    @Environment(BoardStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rotationEnabled") private var rotationEnabled: Bool = true

    private let peekAmount: CGFloat = 16

    private var tone: PostTone { post.tone }
    private var cardHeight: CGFloat { typeSize.isAccessibilitySize ? 300 : 200 }

    var body: some View {
        if post.hasImage {
            imageBundle
        } else {
            postCardContent
                .frame(height: cardHeight)
                .background(cardBackground)
                .animation(.smooth(duration: 0.35), value: post.tone)
                .matchedTransitionSource(id: post.id, in: cardNamespace)
        }
    }

    // MARK: - Stacked bundle (image on top, post card peeking below)

    private var imageBundle: some View {
        VStack(spacing: -peekAmount) {
            imageCard
                .rotationEffect(.degrees(imageCounterRotation))
                .matchedTransitionSource(id: post.id, in: cardNamespace)

            postCardContent
                .frame(height: cardHeight)
                .background(cardBackground)
                .zIndex(1)
                .animation(.smooth(duration: 0.35), value: post.tone)
        }
    }

    private var imageCounterRotation: Double {
        guard rotationEnabled && !reduceMotion else { return 0 }
        return -cardRotation
    }

    @ViewBuilder
    private var imageCard: some View {
        if let urlString = post.imageUrl, let url = URL(string: urlString) {
            BoardAsyncImage(url: url, tone: tone, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: imageCardHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tone.color.opacity(0.4), lineWidth: 0.9)
                }
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tone.color.opacity(0.10))
                }
                .animation(.smooth(duration: 0.35), value: post.tone)
        }
    }

    private var imageCardHeight: CGFloat {
        guard let ratio = post.imageAspectRatio, ratio > 0 else { return 200 }
        let colWidth = (UIScreen.main.bounds.width - 44) / 2
        return min(colWidth / CGFloat(ratio), 300)
    }

    // MARK: - Post card content (shared between plain and bundle variants)

    private var postCardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(post.title)
                .fontStyle(.title3)
                .fontWeight(.heavy)
                .foregroundStyle(.primary)
            Text(post.description)
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            cardAuthorRow
            topReactionsRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardAuthorRow: some View {
        let profile = store.profile(forAuthor: post.author)
        return HStack(spacing: 6) {
            AvatarView(profile: profile, size: .xsmall)
            Text(profile.displayName)
                .fontStyle(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Reactions

    private var topReactionsRow: some View {
        HStack(spacing: 10) {
            ForEach(Array(displayedReactions.enumerated()), id: \.element.reaction) { idx, entry in
                if idx > 0 {
                    Rectangle()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: 1, height: 10)
                }
                reactionChip(entry)
            }
        }
        .allowsHitTesting(false)
        .animation(.snappy(duration: 0.35), value: displayedReactions.map(\.reaction))
    }

    @ViewBuilder
    private func reactionChip(_ entry: ReactionDisplayEntry) -> some View {
        let label = HStack(spacing: 4) {
            Text(entry.reaction.emoji)
                .fontStyle(.caption2)
            Text(entry.count.abbreviated)
                .fontStyle(.caption2)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText(value: Double(entry.count)))
                .animation(.snappy(duration: 0.35), value: entry.count)
        }
        .foregroundStyle(.secondary)

        if entry.isUserSelection {
            label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(tone.color.opacity(scheme == .dark ? 0.28 : 0.16))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tone.color.opacity(0.45), lineWidth: 0.9)
                )
        } else {
            label
                .frame(maxWidth: .infinity)
        }
    }

    private var displayedReactions: [ReactionDisplayEntry] {
        let ranked = Reaction.defaultOrder.enumerated().map { offset, reaction in
            (offset: offset, reaction: reaction, count: post.reactionCounts[reaction] ?? 0)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.offset < rhs.offset
        }

        var entries: [ReactionDisplayEntry] = []

        if let userReaction {
            entries.append(
                ReactionDisplayEntry(
                    reaction: userReaction,
                    count: post.reactionCounts[userReaction] ?? 0,
                    isUserSelection: true
                )
            )
        }

        for item in ranked where entries.count < 3 {
            if item.reaction == userReaction { continue }
            entries.append(
                ReactionDisplayEntry(
                    reaction: item.reaction,
                    count: item.count,
                    isUserSelection: false
                )
            )
        }

        return entries
    }

    // MARK: - Background

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular.tint(tone.color.opacity(0.20)),
                    in: .rect(cornerRadius: 18, style: .continuous)
                )
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(tone.color.opacity(0.5), lineWidth: 0.9)
                }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .glassFallback(tone: tone)
        }
    }
}

private struct ReactionDisplayEntry: Equatable {
    let reaction: Reaction
    let count: Int
    let isUserSelection: Bool
}

/// Resolves a feed card from the store by ID so reaction and tone updates re-render only this cell.
struct FeedGridCard: View {
    let postID: UUID
    var cardNamespace: Namespace.ID? = nil
    var cardRotation: Double = 0
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let post = store.feedPost(id: postID) {
            GridCard(
                post: post,
                userReaction: store.userReaction(for: postID),
                cardNamespace: cardNamespace,
                cardRotation: cardRotation
            )
            .id("\(postID.uuidString)-\(post.tone.rawValue)")
        }
    }
}

extension Shape {
    func glassFallback(tone: PostTone) -> some View {
        self
            .fill(.ultraThinMaterial)
            .stroke(tone.color.opacity(0.5), lineWidth: 0.9)
            .fill(tone.color.opacity(0.20))
    }
}

// MARK: - Conditional matchedTransitionSource

extension View {
    /// Applies matchedTransitionSource only when a namespace is present.
    /// Used so GridCard can own the zoom-transition source without requiring callers to always provide a namespace.
    @ViewBuilder
    func matchedTransitionSource(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
