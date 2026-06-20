//
//  ReactionRealtimeChange.swift
//  On Board
//

import Foundation
import Supabase

struct ReactionRealtimeChange: Sendable, Equatable {
    let postID: UUID
    let userID: UUID
    let previousType: Reaction?
    let newType: Reaction?
}

private struct ReactionRecordPayload: Decodable, Sendable {
    let postId: UUID
    let userId: UUID
    let type: Reaction
}

enum ReactionRealtimeParser {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func parse(_ action: AnyAction) -> ReactionRealtimeChange? {
        do {
            switch action {
            case .insert(let insert):
                let row = try insert.decodeRecord(as: ReactionRecordPayload.self, decoder: decoder)
                return ReactionRealtimeChange(
                    postID: row.postId,
                    userID: row.userId,
                    previousType: nil,
                    newType: row.type
                )
            case .update(let update):
                let row = try update.decodeRecord(as: ReactionRecordPayload.self, decoder: decoder)
                let old = try? update.decodeOldRecord(as: ReactionRecordPayload.self, decoder: decoder)
                return ReactionRealtimeChange(
                    postID: row.postId,
                    userID: row.userId,
                    previousType: old?.type,
                    newType: row.type
                )
            case .delete(let delete):
                let old = try delete.decodeOldRecord(as: ReactionRecordPayload.self, decoder: decoder)
                return ReactionRealtimeChange(
                    postID: old.postId,
                    userID: old.userId,
                    previousType: old.type,
                    newType: nil
                )
            }
        } catch {
            return nil
        }
    }
}
