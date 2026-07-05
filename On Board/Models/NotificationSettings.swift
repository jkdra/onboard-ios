//
//  NotificationSettings.swift
//  On Board
//

import Foundation

/// User preferences for push notifications. Maps to the Supabase `user_settings` table.
struct NotificationSettings: Equatable, Sendable {
    var pushReactions: Bool
    var pushComments: Bool
    var pushNewPosts: Bool
    var pushFollowedPosts: Bool
    
    init(
        pushReactions: Bool = true,
        pushComments: Bool = true,
        pushNewPosts: Bool = true,
        pushFollowedPosts: Bool = true
    ) {
        self.pushReactions = pushReactions
        self.pushComments = pushComments
        self.pushNewPosts = pushNewPosts
        self.pushFollowedPosts = pushFollowedPosts
    }
}

extension NotificationSettings: Codable {
    enum CodingKeys: CodingKey {
        case pushReactions
        case pushComments
        case pushNewPosts
        case pushFollowedPosts
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pushReactions = try container.decodeIfPresent(Bool.self, forKey: .pushReactions) ?? true
        self.pushComments = try container.decodeIfPresent(Bool.self, forKey: .pushComments) ?? true
        self.pushNewPosts = try container.decodeIfPresent(Bool.self, forKey: .pushNewPosts) ?? true
        self.pushFollowedPosts = try container.decodeIfPresent(Bool.self, forKey: .pushFollowedPosts) ?? true
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pushReactions, forKey: .pushReactions)
        try container.encode(pushComments, forKey: .pushComments)
        try container.encode(pushNewPosts, forKey: .pushNewPosts)
        try container.encode(pushFollowedPosts, forKey: .pushFollowedPosts)
    }
}
