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
        draftTitle = livePost.title
        draftDescription = livePost.description
        draftTone = livePost.tone
        draftTags = livePost.tags
        draftImageUrl = livePost.imageUrl
        draftImageAspectRatio = livePost.imageAspectRatio
        selectedEditPhotoData = nil
        selectedEditPhotoItem = nil
        uploadedEditImageUrl = nil
        uploadedEditAspectRatio = nil
        editImageUploadFailed = false
        withAnimation(.smooth(duration: 0.4)) { editMode = true }
    }

    func saveEdits() {
        Task {
            let effectiveImageUrl = uploadedEditImageUrl ?? draftImageUrl
            let effectiveAspectRatio = uploadedEditAspectRatio ?? draftImageAspectRatio
            let succeeded = await store.updatePost(
                id: livePost.id,
                title: draftTitle.trimmed,
                description: draftDescription.trimmed,
                tone: draftTone,
                imageUrl: effectiveImageUrl,
                imageAspectRatio: effectiveAspectRatio,
                tags: draftTags
            )
            guard succeeded else { return }
            withAnimation(.smooth(duration: 0.4)) { editMode = false }
        }
    }

    func cancelEditing() {
        draftTitle = livePost.title
        draftDescription = livePost.description
        draftTone = livePost.tone
        draftTags = livePost.tags
        draftImageUrl = livePost.imageUrl
        draftImageAspectRatio = livePost.imageAspectRatio
        selectedEditPhotoData = nil
        selectedEditPhotoItem = nil
        uploadedEditImageUrl = nil
        uploadedEditAspectRatio = nil
        editImageUploadFailed = false
        withAnimation(.smooth(duration: 0.4)) { editMode = false }
    }

    // MARK: - Comment editing

    func beginCommentEditing(commentID: UUID, body: String) {
        withAnimation(.smooth(duration: 0.35)) { composer.dismiss() }
        editingCommentID = commentID
        draftCommentBody = body
    }

    func confirmCommentEditing() {
        guard let editingCommentID else { return }
        let trimmed = draftCommentBody.trimmed
        guard !trimmed.isEmpty else { return }
        Task {
            await store.updateComment(postID: livePost.id, commentID: editingCommentID, body: trimmed)
            withAnimation(.smooth(duration: 0.35)) {
                self.editingCommentID = nil
                draftCommentBody = ""
            }
        }
    }

    func cancelCommentEditing() {
        withAnimation(.smooth(duration: 0.35)) {
            editingCommentID = nil
            draftCommentBody = ""
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
        selectedEditPhotoData = nil
        selectedEditPhotoItem = nil
        uploadedEditImageUrl = nil
        uploadedEditAspectRatio = nil
        draftImageUrl = nil
        draftImageAspectRatio = nil
        editImageUploadFailed = false
    }

    func loadAndUploadEditImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              UIImage(data: rawData) != nil else { return }
        selectedEditPhotoData = rawData
        editImageUploadFailed = false
        guard let userID = store.currentUserID else { return }
        isUploadingEditImage = true
        defer { isUploadingEditImage = false }
        if let result = await ImageUploader.upload(input: .rawData(rawData), type: .postPhoto, userID: userID) {
            uploadedEditImageUrl = result.url
            uploadedEditAspectRatio = result.aspectRatio
            draftImageUrl = nil
        } else {
            // Drop the failed preview so what's on screen matches what Save keeps
            // (the post's previous image, if any).
            selectedEditPhotoData = nil
            selectedEditPhotoItem = nil
            editImageUploadFailed = true
        }
    }
}
