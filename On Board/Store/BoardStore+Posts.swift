//
//  BoardStore+Posts.swift
//  On Board
//

import Foundation

extension BoardStore {
    func addPost(
        title: String,
        description: String,
        tone: PostTone,
        imageUrl: String? = nil,
        imageAspectRatio: Double? = nil,
        tags: [String] = []
    ) async -> Bool {
        guard canInteractWithBoard, let user = currentUser else { return false }
        // Backstop for the final-hour posting freeze (the UI hides the entry, this blocks any
        // composer left open from before the cutoff).
        guard !BoardSchedule.isWithinFinalHour(weekEnd: activeBoardWeek?.endsAt) else {
            loadError = "Posting is closed for the final hour before the board clears."
            return false
        }
        guard let boardService, let weekID = activeBoardWeek?.id else {
            loadError = isLive
                ? "No active board week is available."
                : "Connect to the On Board backend to post."
            return false
        }

        do {
            let post = try await boardService.createPost(
                weekID: weekID,
                authorID: user.id,
                title: title,
                description: description,
                tone: tone,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio,
                tags: tags
            )
            insertPost(post)
            return true
        } catch {
            loadError = Self.mapLoadError(error)
            return false
        }
    }

    func updatePost(
        id: UUID,
        title: String,
        description: String,
        tone: PostTone,
        imageUrl: String?,
        imageAspectRatio: Double?,
        tags: [String]
    ) async -> Bool {
        guard let index = posts.firstIndex(where: { $0.id == id }),
              canInteract(with: posts[index]),
              canEdit(post: posts[index]) else { return false }

        let existing = posts[index]

        guard let boardService else {
            let updated = Post(
                id: existing.id,
                authorId: existing.authorId,
                boardWeekId: existing.boardWeekId,
                isReadOnly: existing.isReadOnly,
                title: title,
                description: description,
                author: existing.author,
                tone: tone,
                reactionCounts: existing.reactionCounts,
                comments: comments(for: id),
                createdAt: existing.createdAt,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio,
                tags: tags
            )
            replacePost(at: index, with: updated)
            return true
        }

        do {
            let updated = try await boardService.updatePost(
                id: id,
                title: title,
                description: description,
                tone: tone,
                imageUrl: imageUrl,
                imageAspectRatio: imageAspectRatio,
                tags: tags
            )
            replacePost(at: index, with: updated)
            return true
        } catch {
            loadError = Self.mapLoadError(error)
            return false
        }
    }

    func deletePost(id: UUID) async -> Bool {
        guard let index = posts.firstIndex(where: { $0.id == id }),
              canInteract(with: posts[index]),
              canEdit(post: posts[index]) else { return false }

        guard let boardService else {
            loadError = "Connect to the On Board backend to delete posts."
            return false
        }

        do {
            try await boardService.deletePost(id: id)
            removePost(id: id)
            return true
        } catch {
            loadError = Self.mapLoadError(error)
            return false
        }
    }
}
