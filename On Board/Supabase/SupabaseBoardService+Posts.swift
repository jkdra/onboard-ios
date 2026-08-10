//
//  SupabaseBoardService+Posts.swift
//  On Board
//

import Foundation
import Supabase
import os

private let logger = Logger(subsystem: "org.onboardapp.onboard", category: "SupabaseBoardService+Posts")

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
                row.toPost(extraTags: tagsByPost[row.id] ?? [])
            },
            // uniquingKeysWith, not uniqueKeysWithValues: the latter *traps* on a
            // duplicate key. Today the reactions PK (post_id, user_id) makes
            // duplicates impossible, but that safety lives entirely in a database
            // constraint this code can't see — an RPC or join change would turn a
            // data anomaly into a hard crash with no rollback and no error path.
            userReactions: Dictionary(
                reactionRows.compactMap { row in
                    Reaction(rawValue: row.type).map { (row.postId, $0) }
                },
                uniquingKeysWith: { _, latest in latest }
            )
        )
    }

    func createPost(
        weekID: UUID,
        authorID: UUID,
        content: String,
        tone: PostTone,
        toneExplicit: Bool,
        imageUrl: String?,
        imageAspectRatio: Double?,
        tags: [String]
    ) async throws -> Post {
        struct Insert: Encodable {
            let boardWeekId: UUID
            let authorId: UUID
            // Pre-migration wire shape: the posts table still carries NOT
            // NULL title/description columns. title is written empty and
            // description carries the full markup content — the moderation
            // drain reads description, so the judge sees the whole post.
            let title: String
            let description: String
            let tone: PostTone
            /// Did the author PICK this tone, or did "Any Color!" roll it?
            /// Only deliberate picks feed the Favorite Color tally — see the
            /// `tone_explicit_for_favorite_color` migration.
            let toneExplicit: Bool
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
                    title: "",
                    description: content,
                    tone: tone,
                    toneExplicit: toneExplicit,
                    imageUrl: imageUrl,
                    imageAspectRatio: imageAspectRatio
                )
            )
            .select("id")
            .single()
            .execute()
            .value

        // The insert above already committed server-side — from here on, a
        // transient failure must not throw the whole post away, since the
        // caller (BoardStore+Posts.addPost) treats any throw as "post creation
        // failed" and a user retry would create a genuine duplicate row.
        // The enrich fetch is the one piece we can't proceed without, so it
        // gets one retry; tag-attachment failure is tolerated (best-effort —
        // losing tags on a blip is far cheaper than losing the whole post).
        async let enrichedTask = fetchPostByIdWithRetry(id: inserted.id)
        async let tagsAttached: Void = trySetTags(postID: inserted.id, tags: tags)

        let enriched = try await enrichedTask
        await tagsAttached

        // Tags need no re-attachment: new-format content carries its
        // hashtags inline, so toPost derives them.
        return enriched.toPost()
    }

    private func fetchPostByIdWithRetry(id: UUID) async throws -> RemotePostRow {
        do {
            return try await client.rpc("fetch_post_by_id", params: ["p_post_id": id]).execute().value
        } catch {
            try? await Task.sleep(for: .milliseconds(400))
            return try await client.rpc("fetch_post_by_id", params: ["p_post_id": id]).execute().value
        }
    }

    private func trySetTags(postID: UUID, tags: [String]) async {
        struct SetTagsParams: Encodable {
            let p_post_id: UUID
            let p_tags: [String]
        }
        do {
            try await client.rpc("set_post_tags", params: SetTagsParams(p_post_id: postID, p_tags: tags)).execute()
        } catch {
            logger.error("set_post_tags failed for post \(postID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func updatePost(
        id: UUID,
        content: String,
        tone: PostTone,
        toneExplicit: Bool,
        imageUrl: String?,
        imageAspectRatio: Double?,
        tags: [String]
    ) async throws -> Post {
        struct Update: Encodable {
            let title: String
            let description: String
            let tone: PostTone
            let toneExplicit: Bool
            let imageUrl: String?
            let imageAspectRatio: Double?
        }

        try await client
            .from("posts")
            .update(Update(title: "", description: content, tone: tone,
                           toneExplicit: toneExplicit,
                           imageUrl: imageUrl, imageAspectRatio: imageAspectRatio))
            .eq("id", value: id.uuidString)
            .execute()

        // The update above already committed — same reasoning as
        // createPost: don't throw the whole save away over a transient
        // blip in the enrich/tag steps (unlike an insert, retrying an
        // identical update isn't destructive, but it's still wasted round
        // trips and a confusing "failed to save" for a save that landed).
        async let enrichedTask = fetchPostByIdWithRetry(id: id)
        async let tagsAttached: Void = trySetTags(postID: id, tags: tags)

        let enriched = try await enrichedTask
        await tagsAttached

        return enriched.toPost()
    }

    func deletePost(id: UUID) async throws {
        try await client
            .from("posts")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
}
