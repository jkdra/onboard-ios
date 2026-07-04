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
}
