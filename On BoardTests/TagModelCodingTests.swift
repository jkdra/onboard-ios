//
//  TagModelCodingTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

/// The `search_tags` RPC returns `(id, name, post_count)`, decoded into `Tag`
/// through `BoardJSON.decoder` (`.convertFromSnakeCase`). An explicit
/// `case postCount = "post_count"` on `Tag` double-converts and throws
/// `keyNotFound` on every decode — and `TagSelectionView` swallows it with
/// `try?`, so the tag-suggestion list silently goes permanently empty (the
/// picker only ever offers "Create #x", never existing tags). This pins the
/// wire shape so that landmine can't be reintroduced.
@MainActor
struct TagModelCodingTests {
    @Test func decodesSnakeCasePostCountFromSearchTags() throws {
        let id = UUID()
        let json = #"[{"id":"\#(id.uuidString)","name":"testing","post_count":3}]"#.data(using: .utf8)!

        // Qualified: `Testing.Tag` also exists in this file's scope.
        let tags = try BoardJSON.decoder.decode([On_Board.Tag].self, from: json)

        #expect(tags.count == 1)
        #expect(tags.first?.id == id)
        #expect(tags.first?.name == "testing")
        #expect(tags.first?.postCount == 3)
    }
}
