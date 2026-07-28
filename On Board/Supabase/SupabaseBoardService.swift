//
//  SupabaseBoardService.swift
//  On Board
//

import Foundation
import Supabase

final class SupabaseBoardService: BoardService, @unchecked Sendable {
    let client: SupabaseClient

    init?(configuration: AppConfiguration) {
        guard let client = SupabaseClientFactory.client(for: configuration) else {
            return nil
        }
        self.client = client
    }

    init(client: SupabaseClient) {
        self.client = client
    }

    func listAccessibleBoards(for userID: UUID) async throws -> [Board] {
        struct Params: Encodable { let pUserId: UUID }
        return try await client
            .rpc("list_accessible_boards", params: Params(pUserId: userID))
            .execute()
            .value
    }

    func loadActiveBoard(boardID: UUID, for userID: UUID) async throws -> BoardSnapshot {
        let week: BoardWeek = try await client
            .rpc("get_active_board_week", params: ["p_board_id": boardID])
            .execute()
            .value

        async let weekPosts = fetchPosts(forWeek: week.id, userID: userID)
        async let currentProfile = fetchProfile(id: userID)

        let loadedPosts = try await weekPosts
        let profile = try await currentProfile

        let otherAuthorIDs = Array(Set(loadedPosts.posts.compactMap { $0.authorId == profile.id ? nil : $0.authorId }))
        let fetchedProfiles = (try? await fetchProfiles(ids: otherAuthorIDs)) ?? []
        let profiles = mergeProfiles(current: profile, fetched: fetchedProfiles, posts: loadedPosts.posts)

        return BoardSnapshot(
            week: week,
            posts: loadedPosts.posts,
            profiles: profiles,
            userReactions: loadedPosts.userReactions
        )
    }

    func listArchivedWeeks(boardID: UUID, limit: Int = 52, offset: Int = 0) async throws -> [BoardWeek] {
        struct Params: Encodable {
            let pBoardId: UUID
            let pLimit: Int
            let pOffset: Int
            let pArchivedOnly: Bool
        }

        return try await client
            .rpc("list_board_weeks", params: Params(
                pBoardId: boardID,
                pLimit: limit,
                pOffset: offset,
                pArchivedOnly: true
            ))
            .execute()
            .value
    }

    /// `fetched` covers the common case (a real profile row exists). Posts whose
    /// author has no matching row — an account deleted after posting — fall back
    /// to a stub built from the post's denormalized author handle, same as before.
    func mergeProfiles(current: Profile, fetched: [Profile], posts: [Post]) -> [Profile] {
        var byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        var seen = Set([current.id])
        var merged = [current]

        for post in posts {
            guard let authorId = post.authorId, seen.insert(authorId).inserted else { continue }
            if let profile = byID.removeValue(forKey: authorId) {
                merged.append(profile)
            } else {
                merged.append(
                    Profile(
                        id: authorId,
                        handle: post.author,
                        displayName: post.author
                    )
                )
            }
        }

        return merged
    }

    struct UserReactionRow: Decodable, Sendable {
        let postId: UUID
        let type: Reaction
    }

    struct UserCommentVoteRow: Decodable, Sendable {
        let commentId: UUID
        let vote: CommentVote
    }
}
