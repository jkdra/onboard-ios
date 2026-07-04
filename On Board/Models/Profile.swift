//
//  Profile.swift
//  On Board
//
//  Account / user profile model. Maps to the Supabase `profiles`
//  table (one row per authenticated user) and is referenced by
//  `Post.authorId` and `Comment.authorId`.
//

import Foundation

/// A user's account profile.
///
/// `handle` is the unique, case-insensitive `@username` used in
/// URLs and mentions. `displayName` is the free-form name shown in
/// UI. The Supabase row carries a `created_at` column mapped to
/// `joinedAt` here via the standard snake-case decoding strategy.
struct Profile: Identifiable, Hashable, Codable {
    var id: UUID
    let handle: String
    let displayName: String
    let bio: String?
    let avatarUrl: String?
    let joinedAt: Date

    enum CodingKeys: CodingKey {
        case id, handle, displayName, bio, avatarUrl, joinedAt
    }

    init(
        id: UUID = UUID(),
        handle: String,
        displayName: String,
        bio: String? = nil,
        avatarUrl: String? = nil,
        joinedAt: Date = .now
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.joinedAt = joinedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        handle = try container.decode(String.self, forKey: .handle)
        
        // Default to handle if display_name is null in the database
        if let decodedName = try container.decodeIfPresent(String.self, forKey: .displayName) {
            displayName = decodedName
        } else {
            displayName = handle
        }
        
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        
        // Map avatar_emoji to avatarUrl
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        
        // Handle gracefully if created_at is missing or renamed in the database
        joinedAt = try container.decodeIfPresent(Date.self, forKey: .joinedAt) ?? .now
    }

    static func == (lhs: Profile, rhs: Profile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
