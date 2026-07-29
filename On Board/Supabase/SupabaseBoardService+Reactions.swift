//
//  SupabaseBoardService+Reactions.swift
//  On Board
//

import Foundation
import Supabase

extension SupabaseBoardService {
    func setReaction(postID: UUID, userID: UUID, reaction: Reaction?) async throws {
        if let reaction {
            struct Upsert: Encodable {
                let postId: UUID
                let userId: UUID
                let type: Reaction
            }

            try await client
                .from("reactions")
                .upsert(Upsert(postId: postID, userId: userID, type: reaction))
                .execute()
        } else {
            try await client
                .from("reactions")
                .delete()
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
    }
}
