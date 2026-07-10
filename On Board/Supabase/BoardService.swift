//
//  BoardService.swift
//  On Board
//
//  Network boundary for board data. `SupabaseBoardService` is the production
//  implementation; `BoardStore` calls these methods and caches the results.
//

import Foundation

struct BoardSnapshot: Sendable {
    let week: BoardWeek
    let posts: [Post]
    let profiles: [Profile]
    let userReactions: [UUID: Reaction]
}

struct BoardWeekPosts: Sendable {
    let posts: [Post]
    let userReactions: [UUID: Reaction]
}

struct CommentThread: Sendable {
    let comments: [Comment]
    let userVotes: [UUID: CommentVote]
}

enum BoardServiceError: Error, LocalizedError, Sendable {
    case notConfigured
    case missingActiveWeek
    case notAuthenticated
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "The board backend is not configured."
        case .missingActiveWeek:
            "No active board week is available."
        case .notAuthenticated:
            "Sign in to interact with the board."
        case .sessionExpired:
            AuthError.sessionExpired.localizedDescription
        }
    }
}

protocol BoardService: Sendable {
    func listAccessibleBoards(for userID: UUID) async throws -> [Board]
    func loadActiveBoard(boardID: UUID, for userID: UUID) async throws -> BoardSnapshot
    func listArchivedWeeks(boardID: UUID, limit: Int, offset: Int) async throws -> [BoardWeek]
    func fetchPosts(forWeek weekID: UUID, userID: UUID) async throws -> BoardWeekPosts
    func fetchComments(for postID: UUID) async throws -> CommentThread
    func setCommentVote(commentID: UUID, postID: UUID, userID: UUID, vote: CommentVote?) async throws
    func createPost(
        weekID: UUID,
        authorID: UUID,
        title: String,
        description: String,
        tone: PostTone,
        imageUrl: String?,
        imageAspectRatio: Double?,
        tags: [String]
    ) async throws -> Post
    func updatePost(
        id: UUID,
        title: String,
        description: String,
        tone: PostTone,
        imageUrl: String?,
        imageAspectRatio: Double?,
        tags: [String]
    ) async throws -> Post
    func deletePost(id: UUID) async throws
    func createComment(
        postID: UUID,
        authorID: UUID,
        authorHandle: String,
        body: String,
        parentCommentID: UUID?
    ) async throws
    func updateComment(id: UUID, body: String) async throws
    func deleteComment(id: UUID) async throws
    func setReaction(postID: UUID, userID: UUID, reaction: Reaction?) async throws
    func updateProfile(
        id: UUID,
        displayName: String,
        handle: String,
        bio: String?,
        avatarUrl: String?
    ) async throws -> Profile
    func reportContent(
        targetType: ReportTargetType,
        targetID: UUID,
        reason: ReportReason,
        details: String?
    ) async throws
    func blockUser(blockedID: UUID) async throws
    func unblockUser(blockedID: UUID) async throws
    func fetchBlockedUserIDs(for userID: UUID) async throws -> [UUID]
    func fetchProfiles(ids: [UUID]) async throws -> [Profile]
    func fetchNotificationSettings(for userID: UUID) async throws -> NotificationSettings
    func updateNotificationSettings(_ settings: NotificationSettings, for userID: UUID) async throws
    
    func fetchUserReactionCounts(for userID: UUID) async throws -> [Reaction: Int]
    func followUser(id: UUID) async throws
    func unfollowUser(id: UUID) async throws
    func fetchFollowedUserIDs() async throws -> Set<UUID>
    func isFollowing(userID: UUID) async throws -> Bool
    
    func searchTags(query: String) async throws -> [Tag]
}

enum BoardServiceFactory {
    @MainActor
    static func make(configuration: AppConfiguration = .current) -> (any BoardService)? {
        guard configuration.isSupabaseConfigured else { return nil }
        return SupabaseBoardService(configuration: configuration)
    }
}
