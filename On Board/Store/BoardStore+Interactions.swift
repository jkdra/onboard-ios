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

    func addPost(title: String, description: String, tone: PostTone) async {
        guard canInteractWithBoard, let user = currentUser else { return }

        if let boardService, let weekID = activeBoardWeek?.id {
            do {
                let post = try await boardService.createPost(
                    weekID: weekID,
                    authorID: user.id,
                    title: title,
                    description: description,
                    tone: tone
                )
                insertPost(post)
            } catch {
                loadError = error.localizedDescription
            }
            return
        }

        let post = Post(
            authorId: user.id,
            boardWeekId: activeBoardWeek?.id,
            title: title,
            description: description,
            author: user.handle,
            tone: tone
        )
        insertPost(post)
    }

    func updatePost(
        id: UUID,
        title: String,
        description: String,
        tone: PostTone
    ) async {
        guard let index = posts.firstIndex(where: { $0.id == id }),
              canInteract(with: posts[index]),
              canEdit(post: posts[index]) else { return }

        if let boardService {
            do {
                let updated = try await boardService.updatePost(
                    id: id,
                    title: title,
                    description: description,
                    tone: tone
                )
                replacePost(at: index, with: updated)
            } catch {
                loadError = error.localizedDescription
            }
            return
        }

        var local = posts[index]
        local.title = title
        local.description = description
        local.tone = tone
        replacePost(at: index, with: local)
    }

    func updateProfile(
        displayName: String,
        handle: String,
        bio: String?
    ) async {
        guard let currentUserID,
              let index = profiles.firstIndex(where: { $0.id == currentUserID }) else { return }

        if let boardService {
            do {
                let updated = try await boardService.updateProfile(
                    id: currentUserID,
                    displayName: displayName,
                    handle: handle,
                    bio: bio
                )
                profiles[index] = updated
                rebuildCaches()
            } catch {
                loadError = error.localizedDescription
            }
            return
        }

        profiles[index] = Profile(
            id: currentUserID,
            handle: handle,
            displayName: displayName,
            bio: bio,
            avatarEmoji: profiles[index].avatarEmoji,
            joinedAt: profiles[index].joinedAt
        )
        rebuildCaches()
    }

    func updateComment(postID: UUID, commentID: UUID, body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let postIndex = posts.firstIndex(where: { $0.id == postID }),
              canInteract(with: posts[postIndex]) else { return }

        _ = mutateComments(for: postID) { comments in
            updateCommentBody(in: &comments, commentID: commentID, body: trimmed)
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
                loadError = error.localizedDescription
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
                loadError = error.localizedDescription
            }
        }
    }

    // MARK: - Private helpers

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
