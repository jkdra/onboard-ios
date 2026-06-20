//
//  GridCard.swift
//  On Board
//

import SwiftUI

struct GridCard: View {
    let post: Post
    var userReaction: Reaction?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var tone: PostTone { post.tone }

    var body: some View {
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
            topReactionsRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: typeSize.isAccessibilitySize ? 300 : 200)
        .background(cardBackground)
        .animation(.smooth(duration: 0.35), value: post.tone)
    }

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
        .filter { $0.count > 0 }

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
    @Environment(BoardStore.self) private var store

    var body: some View {
        if let post = store.feedPost(id: postID) {
            GridCard(
                post: post,
                userReaction: store.userReaction(for: postID)
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
