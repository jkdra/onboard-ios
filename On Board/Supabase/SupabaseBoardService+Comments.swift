//
//  SupabaseBoardService+Comments.swift
//  On Board
//

import Foundation
import Supabase

extension SupabaseBoardService {
    func fetchComments(for postID: UUID) async throws -> CommentThread {
        async let flatRows: [CommentTreeBuilder.FlatComment] = client
            .rpc("fetch_comments_for_post", params: ["p_post_id": postID])
            .execute()
            .value

        async let votes: [UserCommentVoteRow] = client
            .rpc("fetch_my_comment_votes_for_post", params: ["p_post_id": postID])
            .execute()
            .value

        let flat = try await flatRows
        let voteRows = try await votes

        return CommentThread(
            comments: CommentTreeBuilder.buildTree(from: flat),
            // uniquingKeysWith, not uniqueKeysWithValues — see the note in
            // SupabaseBoardService+Posts.fetchPosts. The comment_votes PK
            // (comment_id, user_id) makes duplicates impossible today; this
            // removes the trap regardless.
            userVotes: Dictionary(
                voteRows.compactMap { row in
                    CommentVote(rawValue: row.vote).map { (row.commentId, $0) }
                },
                uniquingKeysWith: { _, latest in latest }
            )
        )
    }

    func setCommentVote(commentID: UUID, postID: UUID, userID: UUID, vote: CommentVote?) async throws {
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

    func createComment(
        postID: UUID,
        authorID: UUID,
        authorHandle: String,
        body: String,
        parentCommentID: UUID?
    ) async throws -> Comment {
        struct Insert: Encodable {
            let postId: UUID
            let authorId: UUID
            let authorHandle: String
            let body: String
            let parentCommentId: UUID?
        }

        // Row shape a fresh insert returns — no `replies` column (that's a
        // client-side tree built from the flat table), constructed into a
        // real `Comment` below. `nonisolated init(from:)` mirrors
        // RemotePostRow/InsertedID for the same off-main-actor decode reason.
        struct InsertedComment: Decodable {
            let id: UUID
            let authorId: UUID?
            let author: String
            let body: String
            let likeCount: Int
            let dislikeCount: Int
            let createdAt: Date
            nonisolated init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(UUID.self, forKey: .id)
                authorId = try c.decodeIfPresent(UUID.self, forKey: .authorId)
                author = try c.decode(String.self, forKey: .author)
                body = try c.decode(String.self, forKey: .body)
                likeCount = try c.decode(Int.self, forKey: .likeCount)
                dislikeCount = try c.decode(Int.self, forKey: .dislikeCount)
                createdAt = try c.decode(Date.self, forKey: .createdAt)
            }
            private enum CodingKeys: String, CodingKey {
                case id, authorId, author = "authorHandle", body, likeCount, dislikeCount, createdAt
            }
        }

        let inserted: InsertedComment = try await client
            .from("comments")
            .insert(
                Insert(
                    postId: postID,
                    authorId: authorID,
                    authorHandle: authorHandle,
                    body: body,
                    parentCommentId: parentCommentID
                )
            )
            .select()
            .single()
            .execute()
            .value

        return Comment(
            id: inserted.id,
            authorId: inserted.authorId,
            author: inserted.author,
            body: inserted.body,
            likeCount: inserted.likeCount,
            dislikeCount: inserted.dislikeCount,
            replies: [],
            createdAt: inserted.createdAt
        )
    }

    func updateComment(id: UUID, body: String) async throws {
        struct Update: Encodable { let body: String }
        try await client
            .from("comments")
            .update(Update(body: body))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteComment(id: UUID) async throws {
        try await client
            .from("comments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}
