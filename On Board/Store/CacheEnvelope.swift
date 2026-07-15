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
    /// Informational only — there's no TTL/expiry check against this.
    /// Freshness comes from the background revalidation every consumer
    /// (Pop Score, comments, notification settings, the board itself)
    /// already kicks off on read, not from this timestamp.
    let cachedAt: Date
    let boardId: UUID
    let snapshot: BoardSnapshot
    let archivedWeeks: [BoardWeek]
    let popScores: [UUID: [Reaction: Int]]
    let comments: [UUID: [Comment]]
    let commentVotes: [UUID: CommentVote]
    let notificationSettings: NotificationSettings?
}
