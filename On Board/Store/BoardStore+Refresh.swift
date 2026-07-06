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

        do {
            let loaded = try await boardService.fetchPosts(forWeek: week.id, userID: userID)
            mergeWeekPosts(loaded.posts, reactions: loaded.userReactions)
            cachedArchiveWeekIDs.append(week.id)
            evictOldArchiveWeeksIfNeeded()
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
        } catch {
            loadError = Self.mapLoadError(error)
        }
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
