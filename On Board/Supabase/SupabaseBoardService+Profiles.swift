//
//  SupabaseBoardService+Profiles.swift
//  On Board
//

import Foundation
import Supabase

extension SupabaseBoardService {
    func updateProfile(
        id: UUID,
        displayName: String,
        handle: String,
        bio: String?,
        avatarUrl: String?
    ) async throws -> Profile {
        struct Params: Encodable {
            let pDisplayName: String
            let pHandle: String
            let pBio: String?
            let pAvatarUrl: String?
        }

        let profile: Profile = try await client
            .rpc("update_profile", params: Params(
                pDisplayName: displayName,
                pHandle: handle,
                pBio: bio,
                pAvatarUrl: avatarUrl
            ))
            .single()
            .execute()
            .value
        return profile
    }

    func fetchProfile(id: UUID) async throws -> Profile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func fetchNotificationSettings(for userID: UUID) async throws -> NotificationSettings {
        do {
            let settings: NotificationSettings = try await client
                .from("user_settings")
                .select()
                .eq("user_id", value: userID.uuidString)
                .single()
                .execute()
                .value
            return settings
        } catch let error as PostgrestError where error.code == "PGRST116" {
            // Row not found, return defaults
            return NotificationSettings()
        }
    }

    /// Upsert body for `user_settings`.
    ///
    /// No `CodingKeys` — `BoardJSON.encoder` handles camel → snake. Every stored
    /// column must appear here: `pushFollowedPosts` was previously missing, so the
    /// "People You Follow" toggle silently never persisted.
    struct NotificationSettingsPayload: Encodable {
        let userId: UUID
        let pushReactions: Bool
        let pushComments: Bool
        let pushNewPosts: Bool
        let pushFollowedPosts: Bool

        init(userID: UUID, settings: NotificationSettings) {
            self.userId = userID
            self.pushReactions = settings.pushReactions
            self.pushComments = settings.pushComments
            self.pushNewPosts = settings.pushNewPosts
            self.pushFollowedPosts = settings.pushFollowedPosts
        }
    }

    func updateNotificationSettings(_ settings: NotificationSettings, for userID: UUID) async throws {
        try await client
            .from("user_settings")
            .upsert(NotificationSettingsPayload(userID: userID, settings: settings))
            .execute()
    }
    
    func fetchUserReactionCounts(for userID: UUID) async throws -> [Reaction: Int] {
        struct Params: Encodable { let pUserId: UUID }
        
        let response: [String: Int] = try await client
            .rpc("get_user_reaction_counts", params: Params(pUserId: userID))
            .execute()
            .value
            
        var counts: [Reaction: Int] = [:]
        for (key, value) in response {
            if let reaction = Reaction(rawValue: key) {
                counts[reaction] = value
            }
        }
        return counts
    }
    
    /// A single `follows` row, in both directions.
    ///
    /// Deliberately has **no** `CodingKeys`. The shared codecs (`BoardJSON`) apply
    /// `.convertToSnakeCase` / `.convertFromSnakeCase`, so `followingId` already
    /// maps to `following_id` on the wire. Spelling the snake_case name out in a
    /// `CodingKey` silently breaks *decoding*: the strategy camel-cases the
    /// incoming `following_id` to `followingId` first, then fails to find a
    /// CodingKey with that string and throws `keyNotFound`. Encoding still works,
    /// so follows would write to the DB but never read back — which is exactly the
    /// bug this type was extracted to prevent recurring.
    struct FollowRow: Codable, Sendable {
        let followingId: UUID
    }

    func followUser(id: UUID) async throws {
        // upsert, not insert: `follows` has a (follower_id, following_id) primary
        // key, so a plain insert throws a unique-violation whenever local state is
        // stale relative to the server (e.g. followedUserIDs hasn't finished its
        // refresh yet, or the same follow happened from another device) — the
        // desired end state ("I follow them") already holds, so this should no-op
        // rather than surface an error. ignoreDuplicates is required, not optional
        // decoration: without it this emits ON CONFLICT DO UPDATE, and `follows`
        // (by design) has no UPDATE policy, so that path is rejected by RLS.
        try await client
            .from("follows")
            .upsert(FollowRow(followingId: id), onConflict: "follower_id,following_id", ignoreDuplicates: true)
            .execute()
    }
    
    func unfollowUser(id: UUID) async throws {
        try await client
            .from("follows")
            .delete()
            .eq("following_id", value: id.uuidString)
            .execute()
    }
    
    func fetchFollowedUserIDs() async throws -> Set<UUID> {
        let rows: [FollowRow] = try await client
            .from("follows")
            .select("following_id")
            .execute()
            .value

        return Set(rows.map(\.followingId))
    }

    /// Direct existence check for a single profile — RLS already scopes `follows`
    /// reads to rows where you're the follower, so this just asks "does a row for
    /// this following_id exist," with no dependency on followedUserIDs having been
    /// refreshed or being fresh.
    func isFollowing(userID: UUID) async throws -> Bool {
        let rows: [FollowRow] = try await client
            .from("follows")
            .select("following_id")
            .eq("following_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }
}
