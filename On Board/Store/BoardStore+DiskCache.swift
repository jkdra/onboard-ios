//
//  BoardStore+DiskCache.swift
//  On Board
//
//  A single on-disk CacheEnvelope so a warm relaunch can paint before the
//  network responds. See the "Client-Side Cache" section of CLAUDE.md.
//

import Foundation

/// Serial off-main writer for the cache file.
///
/// One instance per process (the cache is one file). `submit` replaces any
/// not-yet-written envelope — latest wins — so a burst of mutations (rapid
/// reaction taps, a comment thread landing) coalesces into one encode+write
/// instead of N. The actor is the serialization: writes can never interleave,
/// and the main thread never blocks on encode or IO.
///
/// Durability contract (why this is safe to take off-main): every mutation
/// this cache records also lives on the server — the file is a warm-start
/// optimization, so the worst case for a lost write is one cold-launch
/// spinner, never data loss. The close-the-app race is handled by
/// `flush()`, awaited from the scenePhase `.background` handler, where iOS
/// grants several seconds — plenty for one small file.
/// MainActor mailbox + detached worker, NOT an actor, deliberately: `submit`
/// must be callable synchronously from `persistToDisk` (also MainActor) so a
/// `flush()` immediately after a persist can never observe the writer before
/// the submission lands — with an actor, the fire-and-forget handoff task
/// raced exactly that way (caught by the cache round-trip tests). The heavy
/// work (encode + IO) still runs detached; only the bookkeeping is main.
private final class BoardCacheWriter {
    static let shared = BoardCacheWriter()

    private var pending: CacheEnvelope?
    private var drainTask: Task<Void, Never>?

    func submit(_ envelope: CacheEnvelope) {
        pending = envelope
        guard drainTask == nil else { return }
        drainTask = Task { await drain() }
    }

    private func drain() async {
        while let next = pending {
            pending = nil
            // BoardJSON.encoder is shared with the Supabase client (which
            // already encodes on its own queues); per-call use is the status
            // quo this inherits, not a new assumption.
            await Task.detached(priority: .utility) {
                if let data = try? BoardJSON.encoder.encode(next) {
                    try? data.write(to: BoardStore.cacheFileURL, options: .atomic)
                }
            }.value
        }
        drainTask = nil
    }

    /// Returns once everything submitted so far is on disk. Loops because a
    /// submit can land while awaiting — flush means *drained*, not "the write
    /// that was in flight when I asked".
    func flush() async {
        while let task = drainTask {
            await task.value
        }
    }

    /// Sign-out path: drop anything queued and wait out any in-flight write,
    /// so the caller's file delete cannot be raced by a resurrection write.
    /// Without this, a pending envelope landing after `clearDiskCache`'s
    /// delete would hand the OLD account's reactions and settings to whoever
    /// signs in next on this device.
    func cancelPendingAndWait() async {
        pending = nil
        while let task = drainTask {
            await task.value
        }
    }
}

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
        toneCounts = envelope.toneCounts ?? [:]
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
    /// Off-main since 2026-08-07 — this used to encode the WHOLE envelope
    /// (posts, comments, profiles, archived weeks) synchronously on the main
    /// actor, on every reaction tap. Now only the envelope VALUE is built here
    /// (cheap copy-on-write struct copies of state this actor owns anyway);
    /// encode + IO happen on `BoardCacheWriter`, which coalesces bursts and
    /// is flushed from the scenePhase `.background` handler so leaving the
    /// app can't outrun a pending write. See the writer's doc for why the
    /// remaining force-quit race only ever costs a cold-launch spinner.
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
            toneCounts: toneCounts,
            comments: commentsByPostID,
            commentVotes: userCommentVotes,
            notificationSettings: notificationSettings
        )
        BoardCacheWriter.shared.submit(envelope)
    }

    /// Awaited from the scenePhase `.background` handler — the app leaving
    /// the foreground is the one moment a coalesced write could still be
    /// pending with no future call to catch it. (Also what tests await
    /// before reading the file.)
    func flushCacheWrites() async {
        await BoardCacheWriter.shared.flush()
    }

    /// Deletes the cache file. Called on sign-out — a cached board/profile/
    /// settings blob must never leak into a different account's session.
    ///
    /// Cancel-then-delete, in that order, inside one task: a coalesced write
    /// landing after the delete would resurrect the old account's cache. The
    /// only writes that could queue after this run belong to the NEXT
    /// session, which starts with a network load long after this task has
    /// completed — and `persistToDisk` no-ops until that session has an
    /// active board week anyway.
    func clearDiskCache() {
        // Immediate best-effort delete first (the common, nothing-pending
        // case stays synchronous), then the guarded pass closes the window
        // where an already-queued write lands after the delete.
        try? FileManager.default.removeItem(at: Self.cacheFileURL)
        Task {
            await BoardCacheWriter.shared.cancelPendingAndWait()
            try? FileManager.default.removeItem(at: Self.cacheFileURL)
        }
    }
}
