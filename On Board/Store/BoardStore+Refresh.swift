//
//  BoardStore+Refresh.swift
//  On Board
//
//  Network refresh: active-board loading (with retry/coalescing), archive
//  week loading with an LRU cache, comment fetches, and notification
//  settings. Archive eviction goes through BoardStore's cachedPostIDs(inWeek:)
//  / removeProxies(for:) rather than touching postsByWeek/postProxies
//  directly, so those stay fully private to BoardStore.swift.
//

import Foundation

extension BoardStore {
    func refreshAccessibleBoards(for userID: UUID) async {
        guard let boardService else { return }
        do {
            accessibleBoards = try await boardService.listAccessibleBoards(for: userID)
        } catch {
            // Non-critical — switcher falls back to currentBoard
        }
    }

    func refreshFollowedUsers(for userID: UUID) async {
        guard let boardService else { return }
        do {
            followedUserIDs = try await boardService.fetchFollowedUserIDs()
        } catch {
            // Non-critical
        }
    }

    func refresh(for userID: UUID?) async {
        guard let boardService, let userID else { return }
        // Never fall back to the sample/dev board on live paths: no assigned
        // board means there is nothing to fetch yet (waitlisted user).
        guard let boardID = currentBoardId else { return }

        if let inFlight = refreshTask {
            if refreshTaskBoardID == boardID {
                await inFlight.value
                return
            }
            // The in-flight load is for a different board (user switched mid-load).
            // Supersede it: cancel, wait it out, then load the selected board.
            inFlight.cancel()
            await inFlight.value
        }

        // A warm hydration below can make hasCachedFeed true "for free," which
        // is exactly how a relaunch skips the loading spinner without any
        // change to the gating logic itself.
        hydrateFromDiskIfNeeded(boardID: boardID)

        // Only treat the cache as warm when it belongs to the board being fetched —
        // on a board switch the old board's feed must not suppress the loading state.
        let hasCachedFeed = activeBoardWeek?.boardId == boardID && !posts.isEmpty

        let task = Task { @MainActor in
            if !hasCachedFeed {
                isLoading = true
            }
            loadError = nil
            defer { isLoading = false }

            // A weak connection can drop a single request (e.g. a zero-byte response),
            // so retry transient connectivity failures a couple of times before
            // surfacing the "Couldn't load board" state.
            var attempt = 0
            while true {
                do {
                    async let snapshot = boardService.loadActiveBoard(boardID: boardID, for: userID)
                    async let archivedWeeks = boardService.listArchivedWeeks(
                        boardID: boardID,
                        limit: 52,
                        offset: 0
                    )
                    apply(try await snapshot, incomingArchivedWeeks: try await archivedWeeks)
                    persistToDisk()
                    await refreshAccessibleBoards(for: userID)
                    await refreshBlockedUsers(for: userID)
                    await refreshFollowedUsers(for: userID)
                    break
                } catch {
                    if Task.isCancelled { break }
                    attempt += 1
                    guard NetworkErrorClassifier.isConnectivityFailure(error),
                          attempt <= Self.maxConnectivityRetries else {
                        loadError = Self.mapLoadError(error)
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(400 * attempt))
                }
            }
        }

        let taskID = UUID()
        refreshTask = task
        refreshTaskID = taskID
        refreshTaskBoardID = boardID
        await task.value
        if refreshTaskID == taskID {
            refreshTask = nil
            refreshTaskID = nil
            refreshTaskBoardID = nil
        }
    }

    func loadArchivedWeek(_ week: BoardWeek, for userID: UUID?) async {
        guard let boardService, let userID else { return }
        guard week.boardId == currentBoardId else { return }

        if cachedArchiveWeekIDs.contains(week.id) {
            cachedArchiveWeekIDs.removeAll { $0 == week.id }
            cachedArchiveWeekIDs.append(week.id)
            Task { await validateArchiveWeek(week, for: userID) }
            return
        }

        // A row-tap prefetch (ArchiveCalendarView) and ArchivedWeekView's own
        // .task both call this for the same week — only one should actually hit
        // the network.
        guard !inFlightArchiveWeekIDs.contains(week.id) else { return }
        inFlightArchiveWeekIDs.insert(week.id)
        defer { inFlightArchiveWeekIDs.remove(week.id) }

        do {
            let loaded = try await boardService.fetchPosts(forWeek: week.id, userID: userID)
            mergeWeekPosts(loaded.posts, reactions: loaded.userReactions)
            cachedArchiveWeekIDs.append(week.id)
            evictOldArchiveWeeksIfNeeded()
            await loadMissingPostAuthorProfiles(in: loaded.posts)
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }

    private func evictOldArchiveWeeksIfNeeded() {
        while cachedArchiveWeekIDs.count > Self.maxCachedArchiveWeeks {
            evictArchiveWeekPosts(weekID: cachedArchiveWeekIDs.removeFirst())
        }
    }

    private func evictArchiveWeekPosts(weekID: UUID) {
        let evictedIDs = cachedPostIDs(inWeek: weekID)
        guard !evictedIDs.isEmpty else { return }
        posts.removeAll { evictedIDs.contains($0.id) }
        for id in evictedIDs {
            commentsByPostID.removeValue(forKey: id)
            userReactions.removeValue(forKey: id)
        }
        removeProxies(for: evictedIDs)
        rebuildCaches()
    }

    private func validateArchiveWeek(_ week: BoardWeek, for userID: UUID) async {
        guard let boardService else { return }
        do {
            let loaded = try await boardService.fetchPosts(forWeek: week.id, userID: userID)
            let cachedIDs = cachedPostIDs(inWeek: week.id)
            let loadedIDs = Set(loaded.posts.map(\.id))
            guard cachedIDs != loadedIDs else { return }
            let staleIDs = cachedIDs.subtracting(loadedIDs)
            if !staleIDs.isEmpty {
                posts.removeAll { staleIDs.contains($0.id) }
            }
            mergeWeekPosts(loaded.posts, reactions: loaded.userReactions)
            await loadMissingPostAuthorProfiles(in: loaded.posts)
        } catch {
            // Keep stale cache on network error
        }
    }

    func loadComments(for postID: UUID) async {
        guard let boardService else { return }
        guard posts.contains(where: { $0.id == postID }) else { return }

        do {
            let thread = try await boardService.fetchComments(for: postID)
            commentsByPostID[postID] = thread.comments
            for (commentID, vote) in thread.userVotes {
                userCommentVotes[commentID] = vote
            }
            await loadMissingCommentAuthorProfiles(in: thread.comments)
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }

    /// `fetch_comments_for_post` only denormalizes each commenter's handle onto
    /// the row, not their avatar/bio — the same gap `mergeProfiles` already
    /// closed for post authors. A commenter who hasn't also authored a post in
    /// the currently-loaded week has no entry in `profiles`, so `profile(forAuthor:)`
    /// falls back to a stub with no avatar. Batch-fetch and merge in whatever's
    /// still missing after the comment tree loads.
    private func loadMissingCommentAuthorProfiles(in comments: [Comment]) async {
        guard let boardService else { return }
        let authorIDs = Set(comments.flatMap(commentAuthorIDs))
        let missingIDs = authorIDs.filter { profile(id: $0) == nil }
        guard !missingIDs.isEmpty else { return }

        guard let fetched = try? await boardService.fetchProfiles(ids: Array(missingIDs)) else { return }
        for profile in fetched {
            upsertProfile(profile)
        }
    }

    /// Archived-week posts arrive with only the author's handle denormalized on
    /// the row (`fetch_posts_for_week` doesn't join `profiles`), so an author who
    /// didn't also post in the currently-loaded active week has no entry in
    /// `profiles`. Without this backfill, `profile(forAuthor:)` fabricates a stub
    /// with a *random* `UUID()` — which then gets used as a real follow target and
    /// trips the `follows_following_id_fkey` constraint (and shows no avatar).
    /// Mirrors `loadMissingCommentAuthorProfiles`.
    private func loadMissingPostAuthorProfiles(in posts: [Post]) async {
        guard let boardService else { return }
        let missingIDs = Set(posts.compactMap(\.authorId)).filter { profile(id: $0) == nil }
        guard !missingIDs.isEmpty else { return }

        guard let fetched = try? await boardService.fetchProfiles(ids: Array(missingIDs)) else { return }
        for profile in fetched {
            upsertProfile(profile)
        }
    }

    private func commentAuthorIDs(from comment: Comment) -> [UUID] {
        var ids = [UUID]()
        if let authorId = comment.authorId { ids.append(authorId) }
        for reply in comment.replies {
            ids.append(contentsOf: commentAuthorIDs(from: reply))
        }
        return ids
    }

    // MARK: - Notification Settings

    func fetchNotificationSettings() async throws -> NotificationSettings {
        guard let boardService, let currentUserID else { throw BoardServiceError.notAuthenticated }
        return try await boardService.fetchNotificationSettings(for: currentUserID)
    }

    func updateNotificationSettings(_ settings: NotificationSettings) async throws {
        guard let boardService, let currentUserID else { throw BoardServiceError.notAuthenticated }
        try await boardService.updateNotificationSettings(settings, for: currentUserID)
    }
}
