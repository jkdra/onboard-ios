//
//  CacheEnvelope.swift
//  On Board
//
//  Everything BoardStore persists to disk so a warm relaunch can paint
//  before the network responds. One file, one shape — see the
//  "Client-Side Cache" section of CLAUDE.md before adding a new field.
//

import Foundation

struct CacheEnvelope: Codable {
    /// Bump only when an existing field's *meaning* changes in a way old
    /// data would misrepresent — adding a new Optional field does not
    /// require a bump. A mismatch is treated as a cache miss, never
    /// partially decoded.
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let cachedAt: Date
    let boardId: UUID
    let snapshot: BoardSnapshot
    let archivedWeeks: [BoardWeek]
    let popScores: [UUID: [Reaction: Int]]
    let comments: [UUID: [Comment]]
    let commentVotes: [UUID: CommentVote]
    let notificationSettings: NotificationSettings?
}
