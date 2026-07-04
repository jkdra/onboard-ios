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
            userVotes: Dictionary(uniqueKeysWithValues: voteRows.map { ($0.commentId, $0.vote) })
        )
    }

    func setCommentVote(commentID: UUID, postID: UUID, userID: UUID, vote: CommentVote?) async throws {
        try await mapAuthErrors {
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
    }

    func createComment(
        postID: UUID,
        authorID: UUID,
        authorHandle: String,
        body: String,
        parentCommentID: UUID?
    ) async throws {
        try await mapAuthErrors {
            struct Insert: Encodable {
                let postId: UUID
                let authorId: UUID
                let authorHandle: String
                let body: String
                let parentCommentId: UUID?
            }

            _ = try await client
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
                .execute()
        }
    }

    func updateComment(id: UUID, body: String) async throws {
        try await mapAuthErrors {
            struct Update: Encodable { let body: String }
            try await client
                .from("comments")
                .update(Update(body: body))
                .eq("id", value: id.uuidString)
                .execute()
        }
    }

    func deleteComment(id: UUID) async throws {
        try await mapAuthErrors {
            try await client
                .from("comments")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        }
    }
}
