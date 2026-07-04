//
//  BoardStore+Comments.swift
//  On Board
//

import Foundation

extension BoardStore {
    func userCommentVote(for commentID: UUID) -> CommentVote? {
        userCommentVotes[commentID]
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

        let tempID = UUID()
        let optimistic = Comment(
            id: tempID,
            authorId: user.id,
            author: user.handle,
            body: trimmed
        )

        if let parentID = parentCommentID {
            _ = mutateComments(for: postID) { comments in
                insertReply(optimistic, parentID: parentID, into: &comments)
            }
        } else {
            commentsByPostID[postID, default: []].append(optimistic)
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
            _ = mutateComments(for: postID) { comments in
                removeComment(commentID: tempID, from: &comments)
            }
            loadError = Self.mapLoadError(error)
            return false
        }
    }

    @discardableResult
    private func insertReply(_ reply: Comment, parentID: UUID, into comments: inout [Comment]) -> Bool {
        for index in comments.indices {
            if comments[index].id == parentID {
                comments[index].replies.append(reply)
                return true
            }
            if insertReply(reply, parentID: parentID, into: &comments[index].replies) {
                return true
            }
        }
        return false
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
