//
//  Tag.swift
//  On Board
//

import Foundation

struct Tag: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let postCount: Int

    // No explicit CodingKeys. The `search_tags` RPC that used to decode into
    // this type is gone — per-post tags now arrive as bare `(post_id, tag_name)`
    // rows via `fetch_tags_for_week` (`SupabaseBoardService.TagRow`), so today
    // this model has no live wire decode path. The no-CodingKeys rule still
    // stands for whenever it crosses PostgREST again: BoardJSON.decoder applies
    // `.convertFromSnakeCase`, renaming the wire key `post_count` to `postCount`
    // *before* key matching, so the synthesized key resolves it. Declaring
    // `case postCount = "post_count"` would make the decoder look for a literal
    // `post_count` key that no longer exists post-conversion, throwing
    // `keyNotFound` on every decode — the snake_case-CodingKeys landmine
    // documented in CLAUDE.md. Pinned by TagModelCodingTests.
}
