//
//  CacheEnvelope.swift
//  On Board
//
//  Everything BoardStore persists to disk so a warm relaunch can paint
//  before the network responds. One file, one shape — see the
//  "Client-Side Cache" section of CLAUDE.md before adding a new field.
//

import Foundation

struct CacheEnvelope: Sendable {
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
    /// Optional so cache files written before Favorite Color existed still
    /// decode (see CLAUDE.md — a new Optional field needs no schema bump).
    let toneCounts: [UUID: [PostTone: Int]]?
    let comments: [UUID: [Comment]]
    let commentVotes: [UUID: CommentVote]
    let notificationSettings: NotificationSettings?

    init(
        schemaVersion: Int,
        cachedAt: Date,
        boardId: UUID,
        snapshot: BoardSnapshot,
        archivedWeeks: [BoardWeek],
        popScores: [UUID: [Reaction: Int]],
        toneCounts: [UUID: [PostTone: Int]]?,
        comments: [UUID: [Comment]],
        commentVotes: [UUID: CommentVote],
        notificationSettings: NotificationSettings?
    ) {
        self.schemaVersion = schemaVersion
        self.cachedAt = cachedAt
        self.boardId = boardId
        self.snapshot = snapshot
        self.archivedWeeks = archivedWeeks
        self.popScores = popScores
        self.toneCounts = toneCounts
        self.comments = comments
        self.commentVotes = commentVotes
        self.notificationSettings = notificationSettings
    }
}

// Explicit nonisolated Codable conformance — synthesized Codable would be
// main-actor-isolated (this module defaults to MainActor isolation), which
// blocks decoding/encoding off-main in `persistToDisk`/`hydrateFromDiskIfNeeded`'s
// `Task.detached` work. Same pattern as `Profile`/`NotificationSettings`.
extension CacheEnvelope: Codable {
    enum CodingKeys: CodingKey {
        case schemaVersion, cachedAt, boardId, snapshot, archivedWeeks
        case popScores, toneCounts, comments, commentVotes, notificationSettings
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        cachedAt = try container.decode(Date.self, forKey: .cachedAt)
        boardId = try container.decode(UUID.self, forKey: .boardId)
        snapshot = try container.decode(BoardSnapshot.self, forKey: .snapshot)
        archivedWeeks = try container.decode([BoardWeek].self, forKey: .archivedWeeks)
        popScores = try container.decode([UUID: [Reaction: Int]].self, forKey: .popScores)
        toneCounts = try container.decodeIfPresent([UUID: [PostTone: Int]].self, forKey: .toneCounts)
        comments = try container.decode([UUID: [Comment]].self, forKey: .comments)
        commentVotes = try container.decode([UUID: CommentVote].self, forKey: .commentVotes)
        notificationSettings = try container.decodeIfPresent(NotificationSettings.self, forKey: .notificationSettings)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(cachedAt, forKey: .cachedAt)
        try container.encode(boardId, forKey: .boardId)
        try container.encode(snapshot, forKey: .snapshot)
        try container.encode(archivedWeeks, forKey: .archivedWeeks)
        try container.encode(popScores, forKey: .popScores)
        try container.encodeIfPresent(toneCounts, forKey: .toneCounts)
        try container.encode(comments, forKey: .comments)
        try container.encode(commentVotes, forKey: .commentVotes)
        try container.encodeIfPresent(notificationSettings, forKey: .notificationSettings)
    }
}
