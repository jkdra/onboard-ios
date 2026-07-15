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
    func followUser(id: UUID) async {
        guard let boardService else { return }
        followedUserIDs.insert(id)
        do {
            try await boardService.followUser(id: id)
            followedUserIDs.insert(id)
        } catch {
            followedUserIDs.remove(id)
            loadError = Self.mapLoadError(error)
        }
    }

    func unfollowUser(id: UUID) async {
        guard let boardService else { return }
        followedUserIDs.remove(id)
        do {
            try await boardService.unfollowUser(id: id)
            followedUserIDs.remove(id)
        } catch {
            followedUserIDs.insert(id)
            loadError = Self.mapLoadError(error)
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
        persistToDisk()
    }

    /// No-op if already warm. Called from PostDetailView on open, so a
    /// tapped-into post's author's Pop Score is ready before (if ever) the
    /// user taps through to that profile.
    func prefetchPopScore(for userID: UUID) {
        guard popScores[userID] == nil else { return }
        Task { await refreshPopScore(for: userID) }
    }
}
