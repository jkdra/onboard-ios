//
//  Tag.swift
//  On Board
//

import Foundation

struct Tag: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let postCount: Int

    // No explicit CodingKeys. This type is decoded from the `search_tags` RPC
    // through BoardJSON.decoder, which applies `.convertFromSnakeCase` — so the
    // wire key `post_count` is renamed to `postCount` *before* key matching, and
    // the synthesized `postCount` key resolves it. Declaring `case postCount =
    // "post_count"` here would make the decoder look for a literal `post_count`
    // key that no longer exists post-conversion, throwing `keyNotFound` on every
    // decode — the exact snake_case-CodingKeys landmine documented in CLAUDE.md
    // (which had silently left the tag picker's suggestion list permanently
    // empty). Pinned by TagModelCodingTests.
}
