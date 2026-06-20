//
//  CommentTreeBuilder.swift
//  On Board
//
//  Builds nested Comment trees from flat Supabase rows.
//

import Foundation

enum CommentTreeBuilder {
    struct FlatComment: Decodable, Sendable {
        let id: UUID
        let authorId: UUID
        let author: String
        let body: String
        let parentCommentId: UUID?
        let likeCount: Int
        let dislikeCount: Int
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case authorId = "author_id"
            case author = "author_handle"
            case body
            case parentCommentId = "parent_comment_id"
            case likeCount = "like_count"
            case dislikeCount = "dislike_count"
            case createdAt = "created_at"
        }
    }

    static func buildTree(from flat: [FlatComment]) -> [Comment] {
        var childrenByParent: [UUID?: [FlatComment]] = [:]
        for comment in flat {
            childrenByParent[comment.parentCommentId, default: []].append(comment)
        }

        func build(parentId: UUID?) -> [Comment] {
            (childrenByParent[parentId] ?? [])
                .sorted { $0.createdAt < $1.createdAt }
                .map { row in
                    Comment(
                        id: row.id,
                        authorId: row.authorId,
                        author: row.author,
                        body: row.body,
                        likeCount: row.likeCount,
                        dislikeCount: row.dislikeCount,
                        replies: build(parentId: row.id),
                        createdAt: row.createdAt
                    )
                }
        }

        return build(parentId: nil)
    }
}
