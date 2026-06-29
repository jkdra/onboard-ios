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

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case joinedAt = "created_at"
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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        handle = try c.decode(String.self, forKey: .handle)
        displayName = try c.decode(String.self, forKey: .displayName)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        joinedAt = try c.decode(Date.self, forKey: .joinedAt)
    }

    static func == (lhs: Profile, rhs: Profile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
