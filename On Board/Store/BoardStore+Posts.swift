//
//  BoardStore+Posts.swift
//  On Board
//

import Foundation

extension BoardStore {
    func addPost(
        content: String,
        tone: PostTone,
        imageUrl: String? = nil,
        imageAspectRatio: Double? = nil,
        tags: [String] = []
    ) async -> Bool {
        guard canInteractWithBoard, let user = currentUser else { return false }
        // Backstop for the posting freeze (the UI disables the entry, this blocks any
        // composer left open from before the cutoff). Covers expiry too: `allowsPosting`
        // is false once the deadline passes, so a stale composer can't write into a week
        // that has already ended while the client waits on the rollover.
        guard BoardSchedule.phase(weekEnd: activeBoardWeek?.endsAt, thresholds: boardThresholds).allowsPosting else {
            loadError = "Posting is closed for the final hour before the board clears."
            return false
        }
        guard let boardService, let weekID = activeBoardWeek?.id else {
            loadError = isLive
                ? "No active board week is available."
                : "Connect to the On Board backend to post."
            return false
        }

        do {
            let post = try await boardService.createPost(
                weekID: weekID,
                authorID: user.id,
                content: content,
                tone: tone,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio,
                tags: tags
            )
            insertPost(post)
            return true
        } catch {
            loadError = Self.mapLoadError(error)
            return false
        }
    }

    func updatePost(
        id: UUID,
        content: String,
        tone: PostTone,
        imageUrl: String?,
        imageAspectRatio: Double?,
        tags: [String]
    ) async -> Bool {
        guard let index = posts.firstIndex(where: { $0.id == id }),
              canInteract(with: posts[index]),
              canEdit(post: posts[index]) else { return false }

        let existing = posts[index]

        guard let boardService else {
            let updated = Post(
                id: existing.id,
                authorId: existing.authorId,
                boardWeekId: existing.boardWeekId,
                isReadOnly: existing.isReadOnly,
                content: content,
                author: existing.author,
                tone: tone,
                reactionCounts: existing.reactionCounts,
                comments: comments(for: id),
                createdAt: existing.createdAt,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio,
                tags: tags
            )
            replacePost(at: index, with: updated)
            return true
        }

        do {
            let updated = try await boardService.updatePost(
                id: id,
                content: content,
                tone: tone,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio,
                tags: tags
            )
            // `posts` can be rewritten by a concurrent refresh/realtime change while
            // the network call is in flight, so the index captured above is stale.
            // Re-resolve by id before writing (mirrors the reaction apply path).
            guard let currentIndex = posts.firstIndex(where: { $0.id == id }) else {
                return true
            }
            replacePost(at: currentIndex, with: updated)
            return true
        } catch {
            loadError = Self.mapLoadError(error)
            return false
        }
    }

    /// Removes the post locally before the network call resolves, not after.
    /// A rapid re-trigger of the same delete (before the UI has reacted to the
    /// first) used to be able to send a duplicate DELETE request, since the
    /// post stayed in `posts` — and thus kept passing this function's own
    /// existence guard — until the first call's await returned. Removing it
    /// up front closes that: a second call fails the `firstIndex` guard
    /// immediately, same as `block`/`unblock`'s optimistic-then-rollback shape.
    func deletePost(id: UUID) async -> Bool {
        guard let index = posts.firstIndex(where: { $0.id == id }),
              canInteract(with: posts[index]),
              canEdit(post: posts[index]) else { return false }

        guard let boardService else {
            loadError = "Connect to the On Board backend to delete posts."
            return false
        }

        let priorPosts = posts
        let priorComments = commentsByPostID
        let priorReactions = userReactions
        removePost(id: id)

        do {
            try await boardService.deletePost(id: id)
            return true
        } catch {
            posts = priorPosts
            commentsByPostID = priorComments
            userReactions = priorReactions
            rebuildCaches()
            loadError = Self.mapLoadError(error)
            return false
        }
    }
}
