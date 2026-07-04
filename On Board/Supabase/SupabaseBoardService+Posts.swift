//
//  SupabaseBoardService+Posts.swift
//  On Board
//

import Foundation
import Supabase

extension SupabaseBoardService {
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

    func createPost(
        weekID: UUID,
        authorID: UUID,
        title: String,
        description: String,
        tone: PostTone,
        imageUrl: String?,
        imageAspectRatio: Double?
    ) async throws -> Post {
        struct Insert: Encodable {
            let boardWeekId: UUID
            let authorId: UUID
            let title: String
            let description: String
            let tone: PostTone
            let imageUrl: String?
            let imageAspectRatio: Double?
        }

        struct InsertedID: Decodable {
            let id: UUID
            nonisolated init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(UUID.self, forKey: .id)
            }
            private enum CodingKeys: String, CodingKey { case id }
        }

        let inserted: InsertedID = try await client
            .from("posts")
            .insert(
                Insert(
                    boardWeekId: weekID,
                    authorId: authorID,
                    title: title,
                    description: description,
                    tone: tone,
                    imageUrl: imageUrl,
                    imageAspectRatio: imageAspectRatio
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
        tone: PostTone,
        imageUrl: String?,
        imageAspectRatio: Double?
    ) async throws -> Post {
        try await mapAuthErrors {
            struct Update: Encodable {
                let title: String
                let description: String
                let tone: PostTone
                let imageUrl: String?
                let imageAspectRatio: Double?
            }

            try await client
                .from("posts")
                .update(Update(title: title, description: description, tone: tone,
                               imageUrl: imageUrl, imageAspectRatio: imageAspectRatio))
                .eq("id", value: id.uuidString)
                .execute()

            let enriched: RemotePostRow = try await client
                .rpc("fetch_post_by_id", params: ["p_post_id": id])
                .execute()
                .value
            return enriched.toPost()
        }
    }

    func deletePost(id: UUID) async throws {
        try await mapAuthErrors {
            try await client
                .from("posts")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        }
    }
}
