//
//  RemotePostRowTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct RemotePostRowTests {
    @Test func decodesPostsWithMetaShape() throws {
        let json = """
        {
          "id": "A0000000-0000-4000-8000-000000000099",
          "board_week_id": "B0000000-0000-4000-8000-000000000001",
          "author_id": "A0000000-0000-4000-8000-000000000001",
          "author": "maya.c",
          "title": "Hello",
          "description": "World",
          "tone": "blue",
          "created_at": "2026-06-15T12:00:00Z",
          "is_read_only": false,
          "reaction_counts": { "like": 3 }
        }
        """.data(using: .utf8)!

        let row = try BoardJSON.decoder.decode(RemotePostRow.self, from: json)
        #expect(row.author == "maya.c")
        #expect(row.reactionCounts[.like] == 3)
        #expect(row.toPost().isReadOnly == false)
    }

    @Test func mergesLegacyLoveCountsIntoLike() throws {
        let json = """
        {
          "id": "A0000000-0000-4000-8000-000000000099",
          "board_week_id": "B0000000-0000-4000-8000-000000000001",
          "author_id": "A0000000-0000-4000-8000-000000000001",
          "author": "maya.c",
          "title": "Hello",
          "description": "World",
          "tone": "blue",
          "created_at": "2026-06-15T12:00:00Z",
          "is_read_only": false,
          "reaction_counts": { "like": 2, "love": 1 }
        }
        """.data(using: .utf8)!

        let row = try BoardJSON.decoder.decode(RemotePostRow.self, from: json)
        #expect(row.reactionCounts[.like] == 3)
        #expect(row.reactionCounts.count == 1)
    }
}
