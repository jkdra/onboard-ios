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
    var isLeadingColumn: Bool = false
    var columnWidth: CGFloat = 0

    @Environment(BoardStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rotationEnabled") private var rotationEnabled: Bool = true

    private let peekAmount: CGFloat = 16

    private var tone: PostTone { post.tone }
    private var cardHeight: CGFloat { typeSize.isAccessibilitySize ? 300 : 200 }

    // MARK: - Body

    var body: some View {
        cardView
            .overlay(alignment: stickerCorner.alignment) {
                if let reaction = userReaction, let user = store.currentUser {
                    ReactionStickerPill(reaction: reaction, profile: user, tone: tone)
                        .offset(x: stickerCorner.overhangX, y: stickerCorner.overhangY)
                        .rotationEffect(.degrees(pillRotation))
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var cardView: some View {
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

    // MARK: - Sticker pill placement

    private enum Corner {
        case topLeading, topTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            }
        }

        var overhangX: CGFloat {
            switch self {
            case .topLeading: -13
            case .topTrailing: 13
            }
        }

        var overhangY: CGFloat { -13 }

        // Tilt as if anchored at the bottom — top leans outward away from card center
        var pillRotationAngle: Double {
            switch self {
            case .topLeading: -6
            case .topTrailing: 6
            }
        }
    }

    private var stickerCorner: Corner {
        guard !typeSize.isAccessibilitySize else { return .topTrailing }
        return isLeadingColumn ? .topTrailing : .topLeading
    }

    private var pillRotation: Double {
        guard rotationEnabled && !typeSize.isAccessibilitySize && !reduceMotion else { return 0 }
        return stickerCorner.pillRotationAngle
    }

    // MARK: - Stacked bundle (image on top, post card peeking below)

    private var imageBundle: some View {
        VStack(spacing: -peekAmount) {
            imageCard
                .rotationEffect(.degrees(imageCounterRotation))

            postCardContent
                .frame(height: cardHeight)
                .background(cardBackground)
                .zIndex(1)
                .animation(.smooth(duration: 0.35), value: post.tone)
        }
        .matchedTransitionSource(id: post.id, in: cardNamespace)
    }

    private var imageCounterRotation: Double {
        guard rotationEnabled && !reduceMotion else { return 0 }
        return -cardRotation
    }

    @ViewBuilder
    private var imageCard: some View {
        if let urlString = post.imageUrl, let url = URL(string: urlString) {
            BoardAsyncImage(url: url, tone: tone, contentMode: .fill, targetWidth: columnWidth > 0 ? columnWidth : nil)
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
        guard let ratio = post.imageAspectRatio, ratio > 0, columnWidth > 0 else { return 200 }
        return min(columnWidth / CGFloat(ratio), 300)
    }

    // MARK: - Post card content

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

    // MARK: - Reactions row (always top 3 by count; user's reaction shown via sticker pill only)

    private var topReactionsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(displayedReactions.enumerated()), id: \.element.reaction) { idx, entry in
                if idx > 0 {
                    Circle()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: 4, height: 4)
                }
                reactionChip(entry)
            }
        }
        .allowsHitTesting(false)
        .animation(.snappy(duration: 0.35), value: displayedReactions.map(\.reaction))
    }

    private func reactionChip(_ entry: ReactionDisplayEntry) -> some View {
        HStack(spacing: 4) {
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
        .frame(maxWidth: .infinity)
    }

    private var displayedReactions: [ReactionDisplayEntry] {
        Array(
            Reaction.defaultOrder
                .map { ReactionDisplayEntry(reaction: $0, count: post.reactionCounts[$0] ?? 0) }
                .sorted { $0.count > $1.count }
                .prefix(3)
        )
    }

    // MARK: - Card background

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

// MARK: - Reaction sticker pill

private struct ReactionStickerPill: View {
    let reaction: Reaction
    let profile: Profile
    let tone: PostTone

    var body: some View {
        HStack(spacing: 3) {
            AvatarView(profile: profile, size: .xsmall)
            Text(reaction.emoji)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(tone.color))
        .allowsHitTesting(false)
    }
}

// MARK: - Supporting types

private struct ReactionDisplayEntry: Equatable {
    let reaction: Reaction
    let count: Int
}

/// Resolves a feed card from the store by ID so reaction and tone updates re-render only this cell.
struct FeedGridCard: View {
    let postID: UUID
    var cardNamespace: Namespace.ID? = nil
    var cardRotation: Double = 0
    var isLeadingColumn: Bool = false
    var columnWidth: CGFloat = 0
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let proxy = store.postProxies[postID] {
            GridCard(
                post: proxy.post,
                userReaction: proxy.reaction,
                cardNamespace: cardNamespace,
                cardRotation: cardRotation,
                isLeadingColumn: isLeadingColumn,
                columnWidth: columnWidth
            )
            .id("\(postID.uuidString)-\(proxy.post.tone.rawValue)")
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
