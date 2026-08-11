//
//  TagRowCodingTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

/// `fetch_tags_for_week` returns `(post_id, tag_name)`. Same `.convertFromSnakeCase`
/// trap as `FollowRow` — and the only caller swallows the throw with `try?`, so a
/// regression here makes every post's tags silently disappear rather than erroring.
@MainActor
struct TagRowCodingTests {
    @Test func decodesSnakeCaseTagRowFromPostgREST() throws {
        let postID = UUID()
        let json = #"[{"post_id":"\#(postID.uuidString)","tag_name":"testing"}]"#.data(using: .utf8)!

        let rows = try BoardJSON.decoder.decode([SupabaseBoardService.TagRow].self, from: json)

        #expect(rows.count == 1)
        #expect(rows.first?.postId == postID)
        #expect(rows.first?.tagName == "testing")
    }
}
