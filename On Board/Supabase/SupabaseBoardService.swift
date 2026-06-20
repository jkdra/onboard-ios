//
//  SupabaseBoardService.swift
//  On Board
//

import Foundation
import Supabase

final class SupabaseBoardService: BoardService, @unchecked Sendable {
    private let client: SupabaseClient

    init?(configuration: AppConfiguration) {
        guard let client = SupabaseClientFactory.client(for: configuration) else {
            return nil
        }
        self.client = client
    }

    init(client: SupabaseClient) {
        self.client = client
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
        let profiles = mergeProfiles(current: profile, posts: loadedPosts.posts)

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
            .rpc(
                "list_board_weeks",
                params: Params(
                    pBoardId: boardID,
                    pLimit: limit,
                    pOffset: offset,
                    pArchivedOnly: true
                )
            )
            .execute()
            .value
    }

    func fetchPosts(forWeek weekID: UUID, userID: UUID) async throws -> BoardWeekPosts {
        async let rows: [RemotePostRow] = client
            .rpc("fetch_posts_for_week", params: ["p_week_id": weekID])
            .execute()
            .value

        async let reactions: [UserReactionRow] = client
            .rpc("fetch_my_reactions_for_week", params: ["p_week_id": weekID])
            .execute()
            .value

        let postRows = try await rows
        let reactionRows = try await reactions

        return BoardWeekPosts(
            posts: postRows.map { $0.toPost() },
            userReactions: Dictionary(uniqueKeysWithValues: reactionRows.map { ($0.postId, $0.type) })
        )
    }

    func fetchComments(for postID: UUID) async throws -> CommentThread {
        let flat: [CommentTreeBuilder.FlatComment] = try await client
            .rpc("fetch_comments_for_post", params: ["p_post_id": postID])
            .execute()
            .value

        let voteRows: [UserCommentVoteRow] = try await client
            .rpc("fetch_my_comment_votes_for_post", params: ["p_post_id": postID])
            .execute()
            .value

        return CommentThread(
            comments: CommentTreeBuilder.buildTree(from: flat),
            userVotes: Dictionary(uniqueKeysWithValues: voteRows.map { ($0.commentId, $0.vote) })
        )
    }

    func setCommentVote(
        commentID: UUID,
        postID: UUID,
        userID: UUID,
        vote: CommentVote?
    ) async throws {
        if let vote {
            struct Upsert: Encodable {
                let commentId: UUID
                let userId: UUID
                let vote: CommentVote
            }

            try await client
                .from("comment_votes")
                .upsert(Upsert(commentId: commentID, userId: userID, vote: vote))
                .execute()
        } else {
            try await client
                .from("comment_votes")
                .delete()
                .eq("comment_id", value: commentID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
    }

    func createPost(
        weekID: UUID,
        authorID: UUID,
        title: String,
        description: String,
        tone: PostTone
    ) async throws -> Post {
        struct Insert: Encodable {
            let boardWeekId: UUID
            let authorId: UUID
            let title: String
            let description: String
            let tone: PostTone
        }

        struct InsertedID: Decodable { let id: UUID }

        let inserted: InsertedID = try await client
            .from("posts")
            .insert(
                Insert(
                    boardWeekId: weekID,
                    authorId: authorID,
                    title: title,
                    description: description,
                    tone: tone
                )
            )
            .select("id")
            .single()
            .execute()
            .value

        let enriched: RemotePostRow = try await client
            .rpc("fetch_post_by_id", params: ["p_post_id": inserted.id])
            .execute()
            .value
        return enriched.toPost()
    }

    func updatePost(
        id: UUID,
        title: String,
        description: String,
        tone: PostTone
    ) async throws -> Post {
        struct Update: Encodable {
            let title: String
            let description: String
            let tone: PostTone
        }

        try await client
            .from("posts")
            .update(Update(title: title, description: description, tone: tone))
            .eq("id", value: id.uuidString)
            .execute()

        let enriched: RemotePostRow = try await client
            .rpc("fetch_post_by_id", params: ["p_post_id": id])
            .execute()
            .value
        return enriched.toPost()
    }

    func setReaction(postID: UUID, userID: UUID, reaction: Reaction?) async throws {
        if let reaction {
            struct Upsert: Encodable {
                let postId: UUID
                let userId: UUID
                let type: Reaction
            }

            try await client
                .from("reactions")
                .upsert(Upsert(postId: postID, userId: userID, type: reaction))
                .execute()
        } else {
            try await client
                .from("reactions")
                .delete()
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
    }

    func updateProfile(
        id: UUID,
        displayName: String,
        handle: String,
        bio: String?
    ) async throws -> Profile {
        struct Update: Encodable {
            let displayName: String
            let handle: String
            let bio: String?
        }

        let profile: Profile = try await client
            .from("profiles")
            .update(Update(displayName: displayName, handle: handle, bio: bio))
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
        return profile
    }

    private func fetchProfile(id: UUID) async throws -> Profile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    private func mergeProfiles(current: Profile, posts: [Post]) -> [Profile] {
        var seen = Set([current.id])
        var merged = [current]

        for post in posts {
            guard let authorId = post.authorId, seen.insert(authorId).inserted else { continue }
            merged.append(
                Profile(
                    id: authorId,
                    handle: post.author,
                    displayName: post.author,
                    avatarEmoji: "🌱"
                )
            )
        }

        return merged
    }

    private struct UserReactionRow: Decodable, Sendable {
        let postId: UUID
        let type: Reaction
    }

    private struct UserCommentVoteRow: Decodable, Sendable {
        let commentId: UUID
        let vote: CommentVote

        enum CodingKeys: String, CodingKey {
            case commentId = "comment_id"
            case vote
        }
    }
}
