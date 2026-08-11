//
//  BoardStore+Profiles.swift
//  On Board
//

import Foundation

extension BoardStore {
    func updateProfile(
        displayName: String,
        handle: String,
        bio: String?,
        avatarUrl: String? = nil,
        birthday: String? = nil,
        showBirthday: Bool? = nil
    ) async {
        guard let currentUserID else { return }

        guard let boardService else {
            loadError = "Connect to the On Board backend to update your profile."
            return
        }

        do {
            let updated = try await boardService.updateProfile(
                id: currentUserID,
                displayName: displayName,
                handle: handle,
                bio: bio,
                avatarUrl: avatarUrl,
                birthday: birthday,
                showBirthday: showBirthday
            )
            upsertProfile(updated)
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }
    
    func checkHandleAvailable(_ handle: String) async -> HandleCheckResult {
        guard let boardService else { return .networkError }

        do {
            let isAvailable = try await boardService.checkHandleAvailable(handle)
            return isAvailable ? .available : .taken
        } catch {
            if NetworkErrorClassifier.isConnectivityFailure(error) {
                return .networkError
            }
            return .taken
        }
    }

    // `refreshFollowedUsers` replaces `followedUserIDs` wholesale, so a board
    // refresh whose fetch began before this write committed can land afterwards
    // and clobber the optimistic change. Re-asserting the confirmed state after
    // the await settles it regardless of which request finishes last.
    //
    // Also supersedes any in-flight follow/unfollow sync for this user — the
    // same guard `setReaction` uses — so a rapid follow→unfollow→follow can't
    // let an earlier request's confirmation/rollback complete after a newer
    // one and invert state that's already moved on.
    func followUser(id: UUID) {
        guard let boardService else { return }
        followedUserIDs.insert(id)
        followSyncTasks[id]?.cancel()
        followSyncTasks[id] = Task {
            defer { followSyncTasks[id] = nil }
            do {
                try await boardService.followUser(id: id)
                guard !Task.isCancelled else { return }
                followedUserIDs.insert(id)
            } catch {
                guard !Task.isCancelled else { return }
                followedUserIDs.remove(id)
                loadError = Self.mapLoadError(error)
            }
        }
    }

    func unfollowUser(id: UUID) {
        guard let boardService else { return }
        followedUserIDs.remove(id)
        followSyncTasks[id]?.cancel()
        followSyncTasks[id] = Task {
            defer { followSyncTasks[id] = nil }
            do {
                try await boardService.unfollowUser(id: id)
                guard !Task.isCancelled else { return }
                followedUserIDs.remove(id)
            } catch {
                guard !Task.isCancelled else { return }
                followedUserIDs.insert(id)
                loadError = Self.mapLoadError(error)
            }
        }
    }

    // MARK: - Pop Score

    func popScore(for userID: UUID) -> [Reaction: Int]? {
        popScores[userID]
    }

    /// Fetches (or, offline, locally aggregates) a profile's Pop Score and
    /// caches it. A revalidation failure is silent — the caller already has
    /// whatever was cached before, if anything, matching the read-vs-write
    /// failure rule (reads that revalidate fail silently; only writes alert).
    func refreshPopScore(for userID: UUID) async {
        // Called on every post open (see prefetchPopScore below) — most of the
        // time this just reconfirms an already-cached score, so only pay for
        // the full-envelope disk write when the fetch actually changed it.
        let previous = popScores[userID]
        if let boardService {
            guard let fetched = try? await boardService.fetchUserReactionCounts(for: userID) else { return }
            popScores[userID] = fetched
        } else {
            // Offline/mock mode has no live service to aggregate reactions
            // server-side, so approximate it from the posts already in memory.
            popScores[userID] = posts
                .filter { $0.authorId == userID }
                .reduce(into: [Reaction: Int]()) { counts, post in
                    for (reaction, count) in post.reactionCounts {
                        counts[reaction, default: 0] += count
                    }
                }
        }
        guard popScores[userID] != previous else { return }
        persistToDisk()
    }

    /// No-op if already warm. Called from PostDetailView on open, so a
    /// tapped-into post's author's Pop Score is ready before (if ever) the
    /// user taps through to that profile.
    func prefetchPopScore(for userID: UUID) {
        guard popScores[userID] == nil else { return }
        Task { await refreshPopScore(for: userID) }
    }

    // MARK: - Favorite Color

    /// The user's resolved Favorite Color, or nil if they haven't earned one
    /// (too few posts, or no dominant tone — see `FavoriteTone.resolve`).
    func favoriteTone(for userID: UUID) -> FavoriteTone? {
        guard let counts = toneCounts[userID] else { return nil }
        return FavoriteTone.resolve(from: counts, userID: userID)
    }

    /// Fetches (or, offline, locally aggregates) a profile's tone tally.
    /// Revalidation read, so a failure is silent and only an actual change
    /// pays for the disk write — same contract as `refreshPopScore`.
    func refreshFavoriteTone(for userID: UUID) async {
        let previous = toneCounts[userID]
        if let boardService {
            guard let fetched = try? await boardService.fetchUserToneCounts(for: userID) else { return }
            toneCounts[userID] = fetched
        } else {
            // Offline/mock mode: approximate from the posts in memory. This
            // undercounts by design — the server tally spans every week ever,
            // and only this week's posts are here.
            toneCounts[userID] = posts
                .filter { $0.authorId == userID }
                .reduce(into: [PostTone: Int]()) { counts, post in
                    counts[post.tone, default: 0] += 1
                }
        }
        guard toneCounts[userID] != previous else { return }
        persistToDisk()
    }
}
