//
//  SupabaseBoardService+Posts.swift
//  On Board
//

import Foundation
import Supabase

extension SupabaseBoardService {
    /// One row of `fetch_tags_for_week` — `(post_id, tag_name)`.
    ///
    /// No `CodingKeys`, for the same reason as `FollowRow`: `BoardJSON.decoder`
    /// applies `.convertFromSnakeCase`, so it camel-cases `post_id`/`tag_name`
    /// *before* matching. Declaring the snake_case spelling in a `CodingKey`
    /// throws `keyNotFound` — and because the only caller swallows that with
    /// `try?`, tags silently vanish instead of surfacing an error.
    struct TagRow: Decodable, Sendable {
        let postId: UUID
        let tagName: String
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

        async let tagRows: [TagRow] = client
            .rpc("fetch_tags_for_week", params: ["p_week_id": weekID])
            .execute()
            .value

        let postRows = try await rows
        let reactionRows = try await reactions
        let postTags = try? await tagRows

        var tagsByPost: [UUID: [String]] = [:]
        if let postTags {
            for pt in postTags { tagsByPost[pt.postId, default: []].append(pt.tagName) }
        }

        return BoardWeekPosts(
            posts: postRows.map { row in
                var post = row.toPost()
                post.tags = tagsByPost[row.id] ?? []
                return post
            },
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
        imageAspectRatio: Double?,
        tags: [String]
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
            
        struct SetTagsParams: Encodable {
            let p_post_id: UUID
            let p_tags: [String]
        }
        try await client.rpc("set_post_tags", params: SetTagsParams(p_post_id: inserted.id, p_tags: tags)).execute()
            
        var post = enriched.toPost()
        post.tags = tags
        return post
    }

    func updatePost(
        id: UUID,
        title: String,
        description: String,
        tone: PostTone,
        imageUrl: String?,
        imageAspectRatio: Double?,
        tags: [String]
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
                
            struct SetTagsParams: Encodable {
                let p_post_id: UUID
                let p_tags: [String]
            }
            try await client.rpc("set_post_tags", params: SetTagsParams(p_post_id: id, p_tags: tags)).execute()
                
            var post = enriched.toPost()
            post.tags = tags
            return post
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
    
    func searchTags(query: String, boardID: UUID) async throws -> [Tag] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else { return [] }
        struct SearchParams: Encodable {
            let prefix: String
            let p_board_id: UUID
            let p_limit: Int
        }
        return try await client
            .rpc("search_tags", params: SearchParams(prefix: cleanQuery, p_board_id: boardID, p_limit: 10))
            .execute()
            .value
    }
}
