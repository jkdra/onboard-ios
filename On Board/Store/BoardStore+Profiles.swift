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
        avatarUrl: String? = nil
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
                avatarUrl: avatarUrl
            )
            upsertProfile(updated)
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }
    
    func followUser(id: UUID) async {
        guard let boardService else { return }
        followedUserIDs.insert(id)
        do {
            try await boardService.followUser(id: id)
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
        } catch {
            followedUserIDs.insert(id)
            loadError = Self.mapLoadError(error)
        }
    }
}
