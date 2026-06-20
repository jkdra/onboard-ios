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

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "The board backend is not configured."
        case .missingActiveWeek:
            "No active board week is available."
        case .notAuthenticated:
            "Sign in to interact with the board."
        }
    }
}

protocol BoardService: Sendable {
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
        tone: PostTone
    ) async throws -> Post
    func updatePost(
        id: UUID,
        title: String,
        description: String,
        tone: PostTone
    ) async throws -> Post
    func setReaction(postID: UUID, userID: UUID, reaction: Reaction?) async throws
    func updateProfile(
        id: UUID,
        displayName: String,
        handle: String,
        bio: String?
    ) async throws -> Profile
}

enum BoardServiceFactory {
    @MainActor
    static func make(configuration: AppConfiguration = .current) -> (any BoardService)? {
        guard configuration.isSupabaseConfigured else { return nil }
        return SupabaseBoardService(configuration: configuration)
    }
}
