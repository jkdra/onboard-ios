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
}
