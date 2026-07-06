//
//  BoardStore+Reactions.swift
//  On Board
//

import Foundation

extension BoardStore {
    func userReaction(for postId: UUID) -> Reaction? {
        userReactions[postId]
    }

    func setReaction(postId: UUID, reaction: Reaction?) {
        guard let index = posts.firstIndex(where: { $0.id == postId }),
              canInteract(with: posts[index]) else { return }

        let previous = userReactions[postId]
        if previous == reaction { return }

        applyReactionChange(
            postId: postId,
            previous: previous,
            reaction: reaction
        )

        guard let boardService, let currentUserID else { return }

        // Supersede any in-flight sync for this post: a rapid second tap must not
        // let the first request's rollback invert state that has already moved on.
        reactionSyncTasks[postId]?.cancel()
        reactionSyncTasks[postId] = Task {
            defer { reactionSyncTasks[postId] = nil }
            do {
                try await boardService.setReaction(
                    postID: postId,
                    userID: currentUserID,
                    reaction: reaction
                )
            } catch {
                // A newer tap cancelled us, or the user has since changed their
                // reaction — either way our optimistic value is stale, so rolling
                // it back would corrupt the current state. Only revert if what we
                // set is still what's shown.
                if Task.isCancelled { return }
                guard userReactions[postId] == reaction else { return }
                applyReactionChange(
                    postId: postId,
                    previous: reaction,
                    reaction: previous
                )
                loadError = Self.mapLoadError(error)
            }
        }
    }

    private func applyReactionChange(
        postId: UUID,
        previous: Reaction?,
        reaction: Reaction?
    ) {
        // Re-resolve the index by id on every apply: between the optimistic update and an
        // async rollback the posts array can be rewritten (refresh, realtime delete, archive
        // eviction), so a captured Int index could be out of bounds (crash) or point at a
        // different post (silent count corruption).
        guard let postIndex = posts.firstIndex(where: { $0.id == postId }) else { return }
        var counts = posts[postIndex].reactionCounts

        if let previous {
            counts[previous] = max(0, (counts[previous] ?? 0) - 1)
        }
        if let reaction {
            userReactions[postId] = reaction
            counts[reaction, default: 0] += 1
        } else {
            userReactions.removeValue(forKey: postId)
        }

        posts[postIndex].reactionCounts = counts
        patchPostInWeekCache(posts[postIndex])
        // Mirror to proxy — mutates proxy.reaction only, not the proxies dict,
        // so only the affected FeedGridCard re-renders.
        postProxies[postId]?.reaction = reaction
    }
}
