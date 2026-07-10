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

    func updateNotificationSettings(_ settings: NotificationSettings, for userID: UUID) async throws {
        struct Payload: Encodable {
            let userId: UUID
            let pushReactions: Bool
            let pushComments: Bool
            let pushNewPosts: Bool

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case pushReactions = "push_reactions"
                case pushComments = "push_comments"
                case pushNewPosts = "push_new_posts"
            }
        }
        let payload = Payload(
            userId: userID,
            pushReactions: settings.pushReactions,
            pushComments: settings.pushComments,
            pushNewPosts: settings.pushNewPosts
        )
        try await client
            .from("user_settings")
            .upsert(payload)
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
    
    func followUser(id: UUID) async throws {
        struct Payload: Encodable {
            let followingId: UUID
            enum CodingKeys: String, CodingKey {
                case followingId = "following_id"
            }
        }
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
            .upsert(Payload(followingId: id), onConflict: "follower_id,following_id", ignoreDuplicates: true)
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
        struct Row: Decodable {
            let followingId: UUID
            enum CodingKeys: String, CodingKey {
                case followingId = "following_id"
            }
        }
        
        let rows: [Row] = try await client
            .from("follows")
            .select("following_id")
            .execute()
            .value
            
        return Set(rows.map(\.followingId))
    }
}
