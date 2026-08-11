//
//  NotificationSettingsPayloadTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

/// The `user_settings` upsert body must carry *every* stored column. `pushFollowedPosts`
/// was absent, so toggling "People You Follow" appeared to work and then reverted.
@MainActor
struct NotificationSettingsPayloadTests {
    @Test func encodesEveryStoredColumnAsSnakeCase() throws {
        let userID = UUID()
        let settings = NotificationSettings(
            pushReactions: true,
            pushComments: false,
            pushNewPosts: true,
            pushFollowedPosts: false
        )

        let data = try BoardJSON.encoder.encode(
            SupabaseBoardService.NotificationSettingsPayload(userID: userID, settings: settings)
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["user_id"] as? String == userID.uuidString)
        #expect(object["push_reactions"] as? Bool == true)
        #expect(object["push_comments"] as? Bool == false)
        #expect(object["push_new_posts"] as? Bool == true)
        // The regression: this key used to be missing entirely.
        #expect(object["push_followed_posts"] as? Bool == false)
    }
}
