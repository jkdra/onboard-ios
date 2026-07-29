//
//  BoardStore+DiskCache.swift
//  On Board
//
//  A single on-disk CacheEnvelope so a warm relaunch can paint before the
//  network responds. See the "Client-Side Cache" section of CLAUDE.md.
//

import Foundation

extension BoardStore {
    /// Not `private` — the test target reads/writes this path directly to
    /// seed and verify cache fixtures without exercising the full app.
    nonisolated static var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("org.onboardapp.board-cache.json")
    }

    /// Hydrates in-memory state from disk if this board isn't already warm.
    /// Call before any "is the cache warm" check (e.g. `refresh(for:)`'s
    /// `hasCachedFeed`) so a successful hydration skips the loading spinner
    /// for free. Any decode failure (corrupt file, mismatched schema version,
    /// or a different board's cache) is treated as a plain cache miss — the
    /// file is deleted and normal network loading proceeds.
    ///
    /// The read + decode of the full envelope happens off-main (a large
    /// cached feed's JSON can be sizable) so a cold launch doesn't stall the
    /// first frame; only applying the result back to `BoardStore`'s
    /// `@MainActor` state runs here.
    func hydrateFromDiskIfNeeded(boardID: UUID) async {
        guard !(activeBoardWeek?.boardId == boardID && !posts.isEmpty) else { return }
        let envelope = await Task.detached(priority: .userInitiated) { () -> CacheEnvelope? in
            guard let data = try? Data(contentsOf: Self.cacheFileURL) else { return nil }
            return try? BoardJSON.decoder.decode(CacheEnvelope.self, from: data)
        }.value

        guard let envelope,
              envelope.schemaVersion == CacheEnvelope.currentSchemaVersion,
              envelope.boardId == boardID
        else {
            try? FileManager.default.removeItem(at: Self.cacheFileURL)
            return
        }
        apply(envelope.snapshot, incomingArchivedWeeks: envelope.archivedWeeks)
        popScores = envelope.popScores
        commentsByPostID = envelope.comments
        userCommentVotes = envelope.commentVotes
        notificationSettings = envelope.notificationSettings
    }

    /// Best-effort disk write of everything currently cacheable. Call after
    /// any successful board load and after any mutation that changes cached
    /// state (block/unblock, notification-settings save) — don't rely solely
    /// on the next natural refresh to capture a mutation, since a force-quit
    /// in between would leave stale content cached. A write failure only
    /// costs a future cold-launch spinner, never correctness.
    ///
    /// A board-less (waitlisted) user has no `activeBoardWeek`, so this is a
    /// no-op for them — their notification settings (and everything else)
    /// simply never persist across a relaunch. Correctness is unaffected
    /// (falls back to a network fetch); it's only the spinner-skip speedup
    /// that doesn't apply to this cohort.
    ///
    /// Stays synchronous on purpose, even though the encode+write is real
    /// CPU/IO work: this is the one thing standing between a mutation and a
    /// force-quit losing it (see above) — dispatching the write to a
    /// detached background task would let the process die before it lands,
    /// silently reintroducing exactly the data loss this function exists to
    /// prevent. Worth revisiting only alongside a durability-preserving
    /// approach (e.g. a coalesced/debounced write on a serial background
    /// queue that's flushed on `scenePhase` background, not fire-and-forget).
    func persistToDisk() {
        guard let activeBoardWeek else { return }
        let activeWeekPosts = posts.filter { $0.boardWeekId == activeBoardWeek.id }
        let snapshot = BoardSnapshot(
            week: activeBoardWeek,
            posts: activeWeekPosts,
            profiles: profiles,
            userReactions: userReactions
        )
        let envelope = CacheEnvelope(
            schemaVersion: CacheEnvelope.currentSchemaVersion,
            cachedAt: .now,
            boardId: activeBoardWeek.boardId,
            snapshot: snapshot,
            archivedWeeks: archivedWeeks,
            popScores: popScores,
            comments: commentsByPostID,
            commentVotes: userCommentVotes,
            notificationSettings: notificationSettings
        )
        guard let data = try? BoardJSON.encoder.encode(envelope) else { return }
        try? data.write(to: Self.cacheFileURL, options: .atomic)
    }

    /// Deletes the cache file. Called on sign-out — a cached board/profile/
    /// settings blob must never leak into a different account's session.
    func clearDiskCache() {
        try? FileManager.default.removeItem(at: Self.cacheFileURL)
    }
}
