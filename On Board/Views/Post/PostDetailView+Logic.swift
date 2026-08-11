//
//  PostDetailView+Logic.swift
//  On Board
//
//  All action functions and derived values for PostDetailView.
//

import SwiftUI
import PhotosUI

extension PostDetailView {

    // MARK: - Derived

    
    // Force-unwrap is safe here: a fixed HTTPS host + `/post/` + a UUID's
    // canonical string form never contains characters `URL(string:)` rejects.
    var shareURL: URL {
        URL(string: "https://onboardapp.org/post/\(livePost.id)")!
    }

    /// Ownership only (unlike `canEdit`, not gated on the week being active),
    /// so report/block stay available on archived content.
    var isOwnPost: Bool {
        store.canEdit(post: livePost)
    }

    // MARK: - Moderation

    func blockUser(_ candidate: BlockCandidate) async {
        do {
            try await store.block(userID: candidate.userID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Blocking the post's author removes it from the store, which fires
            // ContentView's sanitizeNavigationPath synchronously (before this
            // network await even resolves) to pop the now-stale post route —
            // an explicit dismiss() here would race it and, when this post was
            // reached via a profile (.postFromProfile), pop the profile too.
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }

    // MARK: - Post editing

    func beginEditing() {
        cancelCommentEditing()
        resetEditDraft()
        withAnimation(.smooth(duration: 0.4)) { editMode = true }
    }

    func saveEdits() {
        guard !isSavingEdits else { return }
        isSavingEdits = true
        Task {
            defer { isSavingEdits = false }
            let effectiveImageUrl = editPhoto.uploadedURL ?? draftImageUrl
            let effectiveAspectRatio = editPhoto.uploadedAspectRatio ?? draftImageAspectRatio
            let succeeded = await store.updatePost(
                id: livePost.id,
                content: draftContent.trimmed,
                tone: draftTone,
                // The edit-mode tone picker has no "Any Color!" — reaching it
                // at all means the author chose this tone deliberately.
                toneExplicit: true,
                imageUrl: effectiveImageUrl,
                imageAspectRatio: effectiveAspectRatio
            )
            guard succeeded else { return }
            withAnimation(.smooth(duration: 0.4)) { editMode = false }
        }
    }

    func cancelEditing() {
        resetEditDraft()
        withAnimation(.smooth(duration: 0.4)) { editMode = false }
    }

    private func resetEditDraft() {
        draftContent = livePost.content
        draftTone = livePost.tone
        draftImageUrl = livePost.imageUrl
        draftImageAspectRatio = livePost.imageAspectRatio
        editPhoto.reset()
    }

    // MARK: - Comment editing

    func beginCommentEditing(commentID: UUID, body: String) {
        withAnimation(.smooth(duration: 0.35)) { composer.dismiss() }
        commentEdit.begin(commentID: commentID, body: body)
    }

    func confirmCommentEditing() {
        guard let editingCommentID = commentEdit.editingCommentID else { return }
        let trimmed = commentEdit.draftCommentBody.trimmed
        guard !trimmed.isEmpty else { return }
        Task {
            await store.updateComment(postID: livePost.id, commentID: editingCommentID, body: trimmed)
            withAnimation(.smooth(duration: 0.35)) {
                commentEdit.clear()
            }
        }
    }

    func cancelCommentEditing() {
        withAnimation(.smooth(duration: 0.35)) {
            commentEdit.clear()
        }
    }

    func submitComposer() async {
        let trimmed = composer.draft.trimmed
        guard !trimmed.isEmpty else { return }
        let succeeded = await store.addComment(
            postID: livePost.id,
            body: trimmed,
            parentCommentID: composer.target?.replyParentID
        )
        if succeeded {
            withAnimation(.smooth(duration: 0.35)) { composer.finishPosting() }
        }
    }

    // MARK: - Image editing

    func removeEditImage() {
        editPhoto.removeImage()
        draftImageUrl = nil
        draftImageAspectRatio = nil
    }
}
