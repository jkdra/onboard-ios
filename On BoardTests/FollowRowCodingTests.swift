//
//  FollowRowCodingTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

/// `follows` rows round-trip through `BoardJSON`, whose `.convertFromSnakeCase`
/// strategy camel-cases incoming keys before matching them. A `CodingKeys` entry
/// spelling out `"following_id"` therefore breaks decoding while leaving encoding
/// intact — follows write to the DB but never read back, so the Follow button
/// never flips to "Following". These pin both directions.
@MainActor
struct FollowRowCodingTests {
    @Test func decodesSnakeCaseFollowingIDFromPostgREST() throws {
        let id = UUID()
        let json = #"[{"following_id":"\#(id.uuidString)"}]"#.data(using: .utf8)!

        let rows = try BoardJSON.decoder.decode([SupabaseBoardService.FollowRow].self, from: json)

        #expect(rows.count == 1)
        #expect(rows.first?.followingId == id)
    }

    @Test func encodesFollowingIDAsSnakeCaseForPostgREST() throws {
        let id = UUID()

        let data = try BoardJSON.encoder.encode(SupabaseBoardService.FollowRow(followingId: id))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object.keys.contains("following_id"))
        #expect(object["following_id"] as? String == id.uuidString)
    }
}
