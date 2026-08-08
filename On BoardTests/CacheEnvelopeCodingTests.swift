//
//  CacheEnvelopeCodingTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct CacheEnvelopeCodingTests {
    @Test @MainActor func roundTripsThroughBoardJSON() throws {
        let boardID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let profile = Profile.samples[0]
        let post = Post(
            authorId: profile.id,
            boardWeekId: week.id,
            content: "cached post d",
            author: profile.handle
        )
        let envelope = CacheEnvelope(
            schemaVersion: CacheEnvelope.currentSchemaVersion,
            cachedAt: .now,
            boardId: boardID,
            snapshot: BoardSnapshot(
                week: week,
                posts: [post],
                profiles: [profile],
                userReactions: [post.id: .like]
            ),
            archivedWeeks: [],
            popScores: [profile.id: [.like: 3, .hug: 1]],
            comments: [:],
            commentVotes: [:],
            notificationSettings: NotificationSettings(pushComments: false)
        )

        let data = try BoardJSON.encoder.encode(envelope)
        let decoded = try BoardJSON.decoder.decode(CacheEnvelope.self, from: data)

        #expect(decoded.schemaVersion == envelope.schemaVersion)
        #expect(decoded.boardId == boardID)
        #expect(decoded.snapshot.week.id == week.id)
        #expect(decoded.snapshot.posts.first?.id == post.id)
        #expect(decoded.popScores[profile.id]?[.like] == 3)
        #expect(decoded.notificationSettings?.pushComments == false)
    }
}
