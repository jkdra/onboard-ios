//
//  NotificationSettingsTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct NotificationSettingsTests {
    @Test func decodesFromJSONWithSnakeCase() throws {
        let json = """
        {
          "push_reactions": true,
          "push_comments": false,
          "push_new_posts": true
        }
        """.data(using: .utf8)!
        
        let settings = try BoardJSON.decoder.decode(NotificationSettings.self, from: json)
        #expect(settings.pushReactions == true)
        #expect(settings.pushComments == false)
        #expect(settings.pushNewPosts == true)
    }

    @Test func providesDefaultValues() {
        let settings = NotificationSettings()
        #expect(settings.pushReactions == true)
        #expect(settings.pushComments == true)
        #expect(settings.pushNewPosts == true)
    }
}
