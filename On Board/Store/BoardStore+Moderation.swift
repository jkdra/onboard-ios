//
//  BoardStore+Moderation.swift
//  On Board
//
//  Reporting and blocking. Server RLS hides reported/blocked content on the
//  next fetch; these methods additionally remove it from the local session
//  cache immediately so the UI reacts without a round trip.
//
//  Unlike the feed mutations, these throw instead of setting `loadError`:
//  the report sheet and block dialogs surface failures locally (they own the
//  presentation context), except session expiry which is routed through
//  `loadError` so the global handler can sign the user out.
//

import Foundation

extension BoardStore {
    // MARK: - Reporting

    /// Reports a post and hides it locally.
    func report(post: Post, reason: ReportReason, details: String?) async throws {
        guard let boardService else { throw BoardServiceError.notConfigured }
        try await boardService.reportContent(
            targetType: .post,
            targetID: post.id,
            reason: reason,
            details: details
        )
        removePost(id: post.id)
    }

    /// Reports a comment and hides it (and its replies) locally.
    func report(comment: Comment, postID: UUID, reason: ReportReason, details: String?) async throws {
        guard let boardService else { throw BoardServiceError.notConfigured }
        try await boardService.reportContent(
            targetType: .comment,
            targetID: comment.id,
            reason: reason,
            details: details
        )
        removeCommentLocally(commentID: comment.id, postID: postID)
    }

    /// Reports a profile. Profile reports go to the review queue only —
    /// nothing is hidden locally (use block for that).
    func report(profile: Profile, reason: ReportReason, details: String?) async throws {
        guard let boardService else { throw BoardServiceError.notConfigured }
        try await boardService.reportContent(
            targetType: .profile,
            targetID: profile.id,
            reason: reason,
            details: details
        )
    }

    /// Convenience dispatcher for the report sheet.
    func report(target: ReportTarget, reason: ReportReason, details: String?) async throws {
        switch target {
        case .post(let post):
            try await report(post: post, reason: reason, details: details)
        case .comment(let comment, let postID):
            try await report(comment: comment, postID: postID, reason: reason, details: details)
        case .profile(let profile):
            try await report(profile: profile, reason: reason, details: details)
        }
    }

    // MARK: - Blocking

    /// Blocks a user: optimistically removes all their content from the
    /// session cache, then persists. Rolls back on failure.
    func block(userID: UUID) async throws {
        guard userID != currentUserID else { return }
        guard let boardService else { throw BoardServiceError.notConfigured }

        // Snapshot for rollback.
        let priorBlocked = blockedUserIDs
        let priorPosts = posts
        let priorComments = commentsByPostID

        blockedUserIDs.insert(userID)
        removeContentLocally(byAuthor: userID)

        do {
            try await boardService.blockUser(blockedID: userID)
            // A force-quit right after blocking must not leave stale
            // (unblocked) content cached — don't rely solely on the next
            // natural refresh to capture this.
            persistToDisk()
        } catch {
            blockedUserIDs = priorBlocked
            posts = priorPosts
            commentsByPostID = priorComments
            rebuildCaches()
            throw error
        }
    }

    /// Unblocks a user. Their content reappears on the next refresh.
    func unblock(userID: UUID) async throws {
        guard let boardService else { throw BoardServiceError.notConfigured }
        let priorBlocked = blockedUserIDs
        blockedUserIDs.remove(userID)
        do {
            try await boardService.unblockUser(blockedID: userID)
            persistToDisk()
        } catch {
            blockedUserIDs = priorBlocked
            throw error
        }
    }

    func isBlocked(userID: UUID) -> Bool {
        blockedUserIDs.contains(userID)
    }

    /// Refreshes the blocked set from the server. Non-critical — keeps the
    /// last known state on failure.
    func refreshBlockedUsers(for userID: UUID) async {
        guard let boardService else { return }
        if let ids = try? await boardService.fetchBlockedUserIDs(for: userID) {
            blockedUserIDs = Set(ids)
        }
    }

    /// Profiles for the Blocked Users settings screen. Blocked users' content
    /// is filtered out of feeds, so their profiles usually aren't in the
    /// session cache — fetch them directly.
    func blockedProfiles() async throws -> [Profile] {
        guard let boardService else { return [] }
        return try await boardService.fetchProfiles(ids: Array(blockedUserIDs))
            .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }
    }

    /// Maps a moderation error for local presentation. Session expiry is
    /// routed through `loadError` (returns nil) so the global error handler
    /// signs the user out; everything else comes back as an alert.
    func presentableModerationError(_ error: Error) -> PresentableAlertError? {
        let message = Self.mapLoadError(error)
        if message == BoardServiceError.sessionExpired.localizedDescription
            || message == AuthError.sessionExpired.localizedDescription {
            loadError = message
            return nil
        }
        return PresentableAlertError(message: message)
    }

    // MARK: - Local removal

    private func removeCommentLocally(commentID: UUID, postID: UUID) {
        _ = mutateComments(for: postID) { comments in
            Self.removeCommentTree(commentID: commentID, from: &comments)
        }
    }

    private func removeContentLocally(byAuthor authorID: UUID) {
        let removedPostIDs = Set(posts.filter { $0.authorId == authorID }.map(\.id))
        if !removedPostIDs.isEmpty {
            posts.removeAll { removedPostIDs.contains($0.id) }
            for id in removedPostIDs {
                commentsByPostID.removeValue(forKey: id)
                userReactions.removeValue(forKey: id)
            }
        }
        for (postID, var thread) in commentsByPostID {
            if Self.removeCommentTrees(byAuthor: authorID, from: &thread) {
                commentsByPostID[postID] = thread
            }
        }
        rebuildCaches()
    }

    @discardableResult
    private static func removeCommentTree(commentID: UUID, from comments: inout [Comment]) -> Bool {
        if let index = comments.firstIndex(where: { $0.id == commentID }) {
            comments.remove(at: index)
            return true
        }
        for index in comments.indices {
            if removeCommentTree(commentID: commentID, from: &comments[index].replies) {
                return true
            }
        }
        return false
    }

    @discardableResult
    private static func removeCommentTrees(byAuthor authorID: UUID, from comments: inout [Comment]) -> Bool {
        var changed = false
        comments.removeAll {
            let matches = $0.authorId == authorID
            changed = changed || matches
            return matches
        }
        for index in comments.indices {
            if removeCommentTrees(byAuthor: authorID, from: &comments[index].replies) {
                changed = true
            }
        }
        return changed
    }
}
