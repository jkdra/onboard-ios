//
//  GridCard.swift
//  On Board
//

import SwiftUI

struct GridCard: View {
    let post: Post
    var userReaction: Reaction?
    var currentUser: Profile?
    var authorProfile: Profile
    var cardNamespace: Namespace.ID? = nil
    /// Zoom-transition source id. This is the *route* the card navigates to, not the
    /// bare post id: the feed and a pushed ProfileView show the same posts at the same
    /// time, so keying on `post.id` would register two sources for one id in the shared
    /// namespace. `.post` vs `.postFromProfile` keeps them distinct.
    var transitionID: BoardRoute? = nil
    var cardRotation: Double = 0
    var rotationIntensity: Double = 0.6
    var isLeadingColumn: Bool = false
    var columnWidth: CGFloat = 0

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var imageHorizontalPadding: CGFloat {
        guard let ratio = post.imageAspectRatio, ratio > 0 else { return 8 }
        return ratio < 1.0 ? 32 : 8
    }

    private var peekAmount: CGFloat {
        guard let ratio = post.imageAspectRatio, ratio > 0 else { return 20 }
        return ratio < 1.0 ? 64 : 20
    }

    private var tone: PostTone { post.tone }
    
    private var cardHeight: CGFloat {
        if typeSize.isAccessibilitySize { return 300 }
        // The standard iPhone width yields a column of ~174pt.
        // 200pt height / 174pt width ≈ 1.15 ratio.
        let idealHeight = columnWidth * 1.15
        return max(180, min(idealHeight, 260)) // Clamped between 180 and 260
    }

    // MARK: - Body

    /// Slack added around the card purely so the zoom-transition source's frame
    /// contains everything the card *draws*:
    ///
    /// * the reaction sticker overhangs the card by 13pt (`Corner.overhangX/Y`) via an
    ///   `.overlay` + `.offset`, and neither expands a view's frame, so it fell outside
    ///   the source rect and got clipped mid-transition;
    /// * `cardRotation` tilts the card, pushing its corners a couple of points past the
    ///   axis-aligned layout frame.
    ///
    /// The matching `.padding(-transitionSourceInset)` below restores the original
    /// layout footprint, so masonry spacing is untouched.
    private static let transitionSourceInset: CGFloat = 16

    var body: some View {
        cardView
            // Rotation must be applied *beneath* matchedTransitionSource. When the
            // source sits inside an ancestor's rotationEffect (it used to live in
            // BoardFeedView.masonryCell), its screen-space geometry is a rotated quad
            // that the zoom transition can't represent — during an *interactive* pop,
            // which re-resolves source geometry every frame, that mismatch shows up as
            // the card collapsing to a tiny rect before snapping back. A button pop
            // resolves the geometry once and mostly hides it.
            .rotationEffect(.degrees(cardRotation))
            .padding(Self.transitionSourceInset)
            .matchedTransitionSource(id: transitionID, in: cardNamespace)
            .padding(-Self.transitionSourceInset)
            .contentShape(.rect)
    }

    @ViewBuilder
    private var cardView: some View {
        if post.hasImage {
            imageBundle
        } else {
            textCard
                .overlay(alignment: stickerCorner.alignment) { stickerPill }
        }
    }

    private var textCard: some View {
        postCardContent
            .frame(height: cardHeight)
            .background(cardBackground)
            .animation(.smooth(duration: 0.35), value: post.tone)
    }

    @ViewBuilder
    private var stickerPill: some View {
        if let reaction = userReaction, let user = currentUser {
            ReactionStickerPill(reaction: reaction, profile: user, tone: tone)
                .offset(x: stickerCorner.overhangX, y: stickerCorner.overhangY)
                .rotationEffect(.degrees(pillRotation))
                .transition(.identity)
                .allowsHitTesting(false)
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
        // Point outward (toward the screen edge's generous safe-area margin),
        // not inward at the narrow 12pt inter-column gutter. The sticker's
        // overhang (13pt) is wider than that gutter, so an inward-facing pill
        // can cross into the neighboring column's card — which, since the two
        // masonry columns are separate LazyVStacks, may render on top of it
        // depending on staggered row heights. Facing outward removes the
        // contested space entirely.
        return isLeadingColumn ? .topLeading : .topTrailing
    }

    private var pillRotation: Double {
        guard rotationIntensity > 0 && !typeSize.isAccessibilitySize && !reduceMotion else { return 0 }
        return stickerCorner.pillRotationAngle * rotationIntensity
    }

    // MARK: - Stacked bundle (image on top, post card peeking below)

    private var imageBundle: some View {
        VStack(spacing: -peekAmount) {
            imageCard
                .rotationEffect(.degrees(imageCounterRotation))

            textCard
                .overlay(alignment: stickerCorner.alignment) { stickerPill }
                .zIndex(1)
        }
    }

    private var imageCounterRotation: Double {
        guard rotationIntensity > 0 && !reduceMotion else { return 0 }
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
                        .stroke(tone.color.opacity(0.4), lineWidth: 1.2)
                }
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tone.color.opacity(0.10))
                }
                .padding(.horizontal, imageHorizontalPadding)
                .animation(.smooth(duration: 0.35), value: post.tone)
        }
    }

    private var imageCardHeight: CGFloat {
        let effectiveWidth = max(columnWidth - (imageHorizontalPadding * 2), 0)
        guard let ratio = post.imageAspectRatio, ratio > 0, effectiveWidth > 0 else { return 164 }
        let maxHeight: CGFloat = ratio < 1.0 ? 180 : 248
        return min(effectiveWidth / CGFloat(ratio), maxHeight)
    }

    // MARK: - Post card content

    private var postCardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(post.title)
                .fontStyle(.title3)
                .fontWeight(.heavy)
                .foregroundStyle(.primary)
                // Matches the composer's own cap (NewPostView's title field is
                // `lineLimit(1...3)`) — without this, an unusually long title can
                // overflow the card's fixed `cardHeight` in the masonry grid.
                .lineLimit(3)
                .truncationMode(.tail)
            Text(post.description)
                .font(.custom("ZalandoSansSemiExpanded-Regular", size: 14, relativeTo: .callout))
                .fontWeight(.regular)
                .opacity(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .truncationMode(.tail)
                
            if !post.tags.isEmpty {
                tagsRow
            }
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom) {
                    topReactionsRow
                    Spacer(minLength: 4)
                    cardAuthorRow
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    cardAuthorRow
                    topReactionsRow
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Tags are unbounded (a post can carry several), but the card is a fixed-width
    // masonry column with no room to scroll. ViewThatFits tries showing all of them
    // first, then progressively fewer with a "+N" badge standing in for the rest —
    // it always lands on the last candidate (a single tag + overflow badge) if
    // nothing wider fits, so there's never a case with no valid layout.
    private var tagsRow: some View {
        // ViewThatFits picks the first candidate that fits; it can't enumerate a
        // dynamic ForEach as separate candidates, so these are spelled out. Showing
        // 4 down to 1 covers every real post (samples top out around 3 tags) — if a
        // post ever had more, several early candidates would just collapse to the
        // same "N tags + overflow" width and get skipped over harmlessly.
        ViewThatFits(in: .horizontal) {
            tagsRow(showing: 4)
            tagsRow(showing: 3)
            tagsRow(showing: 2)
            tagsRow(showing: 1)
        }
    }

    private func tagsRow(showing count: Int) -> some View {
        let shown = post.tags.prefix(count)
        let overflow = post.tags.count - count
        return HStack(spacing: 6) {
            ForEach(Array(shown), id: \.self) { tagChip("#\($0)") }
            if overflow > 0 {
                tagChip("+\(overflow)")
            }
        }
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .fontStyle(.caption2)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.1))
            .clipShape(Capsule())
    }

    // Feed cards show a timestamp instead of the author — authorship is quiet on the
    // grid (not hidden). The opened post detail still shows the author + profile link.
    private var cardAuthorRow: some View {
        HStack(spacing: 4) {
            Text(post.createdAt.boardRelativeAge)
                .lineLimit(1)
        }
        .fontStyle(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Reactions row (always top 3 by count; user's reaction shown via sticker pill only)

    private var topReactionsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(displayedReactions.enumerated()), id: \.element.reaction) { idx, entry in
                if idx > 0 {
                    Circle()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: 4, height: 4)
                        .padding(.horizontal, 6)
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
                        .stroke(tone.color.opacity(0.5), lineWidth: 1.2)
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
        .padding(3)
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
    var transitionID: BoardRoute? = nil
    var cardRotation: Double = 0
    var isLeadingColumn: Bool = false
    var columnWidth: CGFloat = 0
    @Environment(BoardStore.self) private var store
    @AppStorage("rotationIntensity") private var rotationIntensity: Double = 0.6

    var body: some View {
        if let proxy = store.postProxies[postID] {
            GridCard(
                post: proxy.post,
                userReaction: proxy.reaction,
                currentUser: store.currentUser,
                authorProfile: store.profile(forAuthor: proxy.post.author),
                cardNamespace: cardNamespace,
                transitionID: transitionID,
                cardRotation: cardRotation,
                rotationIntensity: rotationIntensity,
                isLeadingColumn: isLeadingColumn,
                columnWidth: columnWidth
            )
            // id is the post alone — including tone here would force a full
            // remount on every tone change, which destroys and recreates the
            // view AT the new color, so the `.animation(value: post.tone)`
            // modifiers below (textCard/imageCard) never see an old value to
            // cross-fade from and the tone change hard-cuts instead.
            .id(postID.uuidString)
        }
    }
}
