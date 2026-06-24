//
//  BoardStore+Interactions.swift
//  On Board
//
//  Optimistic mutations for posts, reactions, comments, and profiles.
//  When live, changes apply locally first then sync to Supabase.
//

import Foundation

extension BoardStore {
    func userReaction(for postId: UUID) -> Reaction? {
        userReactions[postId]
    }

    func userCommentVote(for commentID: UUID) -> CommentVote? {
        userCommentVotes[commentID]
    }

    func addPost(
        title: String,
        description: String,
        tone: PostTone,
        imageUrl: String? = nil,
        imageAspectRatio: Double? = nil
    ) async -> Bool {
        guard canInteractWithBoard, let user = currentUser else { return false }
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
                title: title,
                description: description,
                tone: tone,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio
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
        title: String,
        description: String,
        tone: PostTone,
        imageUrl: String?,
        imageAspectRatio: Double?
    ) async {
        guard let index = posts.firstIndex(where: { $0.id == id }),
              canInteract(with: posts[index]),
              canEdit(post: posts[index]) else { return }

        let existing = posts[index]

        guard let boardService else {
            let updated = Post(
                id: existing.id,
                authorId: existing.authorId,
                boardWeekId: existing.boardWeekId,
                isReadOnly: existing.isReadOnly,
                title: title,
                description: description,
                author: existing.author,
                tone: tone,
                reactionCounts: existing.reactionCounts,
                comments: comments(for: id),
                createdAt: existing.createdAt,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio
            )
            replacePost(at: index, with: updated)
            return
        }

        do {
            let updated = try await boardService.updatePost(
                id: id,
                title: title,
                description: description,
                tone: tone,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio
            )
            replacePost(at: index, with: updated)
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }

    func deletePost(id: UUID) async -> Bool {
        guard let index = posts.firstIndex(where: { $0.id == id }),
              canInteract(with: posts[index]),
              canEdit(post: posts[index]) else { return false }

        guard let boardService else {
            loadError = "Connect to the On Board backend to delete posts."
            return false
        }

        do {
            try await boardService.deletePost(id: id)
            removePost(id: id)
            return true
        } catch {
            loadError = Self.mapLoadError(error)
            return false
        }
    }

    func addComment(
        postID: UUID,
        body: String,
        parentCommentID: UUID? = nil
    ) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let user = currentUser,
              let postIndex = posts.firstIndex(where: { $0.id == postID }),
              canInteract(with: posts[postIndex]) else { return false }

        guard let boardService else {
            loadError = "Connect to the On Board backend to comment."
            return false
        }

        do {
            try await boardService.createComment(
                postID: postID,
                authorID: user.id,
                authorHandle: user.handle,
                body: trimmed,
                parentCommentID: parentCommentID
            )
            await loadComments(for: postID)
            return true
        } catch {
            loadError = Self.mapLoadError(error)
            return false
        }
    }

    func updateComment(postID: UUID, commentID: UUID, body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let postIndex = posts.firstIndex(where: { $0.id == postID }),
              canInteract(with: posts[postIndex]),
              let existing = comments(for: postID).comment(with: commentID),
              canEdit(comment: existing) else { return }

        guard let boardService else {
            loadError = "Connect to the On Board backend to edit comments."
            return
        }

        let previous = existing.body
        _ = mutateComments(for: postID) { comments in
            updateCommentBody(in: &comments, commentID: commentID, body: trimmed)
        }

        do {
            try await boardService.updateComment(id: commentID, body: trimmed)
        } catch {
            _ = mutateComments(for: postID) { comments in
                updateCommentBody(in: &comments, commentID: commentID, body: previous)
            }
            loadError = Self.mapLoadError(error)
        }
    }

    func deleteComment(postID: UUID, commentID: UUID) async -> Bool {
        guard let postIndex = posts.firstIndex(where: { $0.id == postID }),
              canInteract(with: posts[postIndex]),
              let existing = comments(for: postID).comment(with: commentID),
              canEdit(comment: existing) else { return false }

        guard let boardService else {
            loadError = "Connect to the On Board backend to delete comments."
            return false
        }

        let snapshot = comments(for: postID)
        guard var thread = commentsByPostID[postID],
              removeComment(commentID: commentID, from: &thread) else { return false }
        commentsByPostID[postID] = thread

        do {
            try await boardService.deleteComment(id: commentID)
            return true
        } catch {
            commentsByPostID[postID] = snapshot
            loadError = Self.mapLoadError(error)
            return false
        }
    }

    func updateProfile(
        displayName: String,
        handle: String,
        bio: String?,
        avatarUrl: String? = nil
    ) async {
        guard let currentUserID,
              let index = profiles.firstIndex(where: { $0.id == currentUserID }) else { return }

        guard let boardService else {
            loadError = "Connect to the On Board backend to update your profile."
            return
        }

        do {
            let updated = try await boardService.updateProfile(
                id: currentUserID,
                displayName: displayName,
                handle: handle,
                bio: bio,
                avatarUrl: avatarUrl
            )
            profiles[index] = updated
            rebuildCaches()
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }

    func setReaction(postId: UUID, reaction: Reaction?) {
        guard let index = posts.firstIndex(where: { $0.id == postId }),
              canInteract(with: posts[index]) else { return }

        let previous = userReactions[postId]
        if previous == reaction { return }

        applyReactionChange(
            postIndex: index,
            postId: postId,
            previous: previous,
            reaction: reaction
        )

        guard let boardService, let currentUserID else { return }
        Task {
            do {
                try await boardService.setReaction(
                    postID: postId,
                    userID: currentUserID,
                    reaction: reaction
                )
            } catch {
                applyReactionChange(
                    postIndex: index,
                    postId: postId,
                    previous: reaction,
                    reaction: previous
                )
                loadError = Self.mapLoadError(error)
            }
        }
    }

    func setCommentVote(commentID: UUID, postID: UUID, vote: CommentVote?) {
        guard let postIndex = posts.firstIndex(where: { $0.id == postID }),
              canInteract(with: posts[postIndex]) else { return }

        let previous = userCommentVotes[commentID]
        if previous == vote { return }

        applyCommentVoteChange(
            postID: postID,
            commentID: commentID,
            previous: previous,
            vote: vote
        )

        guard let boardService, let currentUserID else { return }
        Task {
            do {
                try await boardService.setCommentVote(
                    commentID: commentID,
                    postID: postID,
                    userID: currentUserID,
                    vote: vote
                )
            } catch {
                applyCommentVoteChange(
                    postID: postID,
                    commentID: commentID,
                    previous: vote,
                    vote: previous
                )
                loadError = Self.mapLoadError(error)
            }
        }
    }

    // MARK: - Private helpers

    @discardableResult
    private func removeComment(commentID: UUID, from comments: inout [Comment]) -> Bool {
        if let index = comments.firstIndex(where: { $0.id == commentID }) {
            comments.remove(at: index)
            return true
        }

        for index in comments.indices {
            if removeComment(commentID: commentID, from: &comments[index].replies) {
                return true
            }
        }
        return false
    }

    private func applyReactionChange(
        postIndex: Int,
        postId: UUID,
        previous: Reaction?,
        reaction: Reaction?
    ) {
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
    }

    private func applyCommentVoteChange(
        postID: UUID,
        commentID: UUID,
        previous: CommentVote?,
        vote: CommentVote?
    ) {
        _ = mutateComments(for: postID) { comments in
            if let previous {
                adjustCommentVoteCounts(
                    in: &comments,
                    commentID: commentID,
                    vote: previous,
                    delta: -1
                )
            }
            if let vote {
                adjustCommentVoteCounts(
                    in: &comments,
                    commentID: commentID,
                    vote: vote,
                    delta: 1
                )
            }
            return true
        }

        if let vote {
            userCommentVotes[commentID] = vote
        } else {
            userCommentVotes.removeValue(forKey: commentID)
        }
    }

    @discardableResult
    private func updateCommentBody(
        in comments: inout [Comment],
        commentID: UUID,
        body: String
    ) -> Bool {
        for index in comments.indices {
            if comments[index].id == commentID {
                comments[index].body = body
                return true
            }
            if updateCommentBody(in: &comments[index].replies, commentID: commentID, body: body) {
                return true
            }
        }
        return false
    }

    @discardableResult
    private func adjustCommentVoteCounts(
        in comments: inout [Comment],
        commentID: UUID,
        vote: CommentVote,
        delta: Int
    ) -> Bool {
        for index in comments.indices {
            if comments[index].id == commentID {
                switch vote {
                case .like:
                    comments[index].likeCount = max(0, comments[index].likeCount + delta)
                case .dislike:
                    comments[index].dislikeCount = max(0, comments[index].dislikeCount + delta)
                }
                return true
            }
            if adjustCommentVoteCounts(
                in: &comments[index].replies,
                commentID: commentID,
                vote: vote,
                delta: delta
            ) {
                return true
            }
        }
        return false
    }
}
