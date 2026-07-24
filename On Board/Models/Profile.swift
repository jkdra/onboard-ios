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
    let birthday: String?
    let showBirthday: Bool
    let joinedAt: Date
    /// Timestamps of recent handle changes (server-maintained). Drives the
    /// client's "2 changes per 14 days" gate so the username field can gray out
    /// *before* the user tries — the same rule is enforced in `update_profile`.
    let handleChangeHistory: [Date]?

    enum CodingKeys: CodingKey {
        case id, handle, displayName, bio, avatarUrl, joinedAt, createdAt, birthday, showBirthday, handleChangeHistory
    }

    nonisolated init(
        id: UUID = UUID(),
        handle: String,
        displayName: String,
        bio: String? = nil,
        avatarUrl: String? = nil,
        birthday: String? = nil,
        showBirthday: Bool = false,
        joinedAt: Date = .now,
        handleChangeHistory: [Date]? = nil
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.birthday = birthday
        self.showBirthday = showBirthday
        self.joinedAt = joinedAt
        self.handleChangeHistory = handleChangeHistory
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
        
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        
        birthday = try container.decodeIfPresent(String.self, forKey: .birthday)
        showBirthday = try container.decodeIfPresent(Bool.self, forKey: .showBirthday) ?? false
        
        // The profiles table stores this as created_at (decoded as createdAt
        // by the snake-case strategy) — joinedAt is only in local fixtures.
        joinedAt = try container.decodeIfPresent(Date.self, forKey: .joinedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? .now

        // `try?`: a malformed/absent array must never break the whole profile
        // decode — worst case we treat the handle as freely changeable and the
        // server still enforces the real limit.
        handleChangeHistory = (try? container.decodeIfPresent([Date].self, forKey: .handleChangeHistory)) ?? nil
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(handle, forKey: .handle)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(birthday, forKey: .birthday)
        try container.encode(showBirthday, forKey: .showBirthday)
        try container.encode(joinedAt, forKey: .joinedAt)
        try container.encodeIfPresent(handleChangeHistory, forKey: .handleChangeHistory)
    }

    static func == (lhs: Profile, rhs: Profile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Display name is optional — a user can identify by just their handle.
    /// Use this instead of `displayName` anywhere it's shown as an identity
    /// (profile header, post/comment author rows, settings) so an empty
    /// display name falls back to `@handle` consistently everywhere.
    var displayNameOrHandle: String {
        displayName.isEmpty ? handle : displayName
    }

    // MARK: - Handle change limit (2 per rolling 14 days)

    /// When the user may next change their username, or nil if they can change
    /// it right now. Mirrors the server rule so the UI can gate proactively.
    var handleChangeAvailableAt: Date? {
        let window: TimeInterval = 14 * 24 * 60 * 60
        let cutoff = Date().addingTimeInterval(-window)
        let recent = (handleChangeHistory ?? []).filter { $0 > cutoff }
        guard recent.count >= 2, let oldest = recent.min() else { return nil }
        return oldest.addingTimeInterval(window)
    }

    /// True when the username may be changed now.
    var canChangeHandle: Bool {
        guard let available = handleChangeAvailableAt else { return true }
        return available <= .now
    }
}
