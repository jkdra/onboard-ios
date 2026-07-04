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

    var shareText: String {
        "\(livePost.title)\n\n\(livePost.description)\n\n— \(livePost.author) on On Board"
    }

    var reportURL: URL {
        var components = URLComponents(url: AppLinks.reportMailURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Report post on On Board"),
            URLQueryItem(
                name: "body",
                value: "Post ID: \(livePost.id.uuidString)\nAuthor: \(livePost.author)\nTitle: \(livePost.title)"
            )
        ]
        return components.url ?? AppLinks.reportMailURL
    }

    // MARK: - Post editing

    func beginEditing() {
        cancelCommentEditing()
        draftTitle = livePost.title
        draftDescription = livePost.description
        draftTone = livePost.tone
        draftImageUrl = livePost.imageUrl
        draftImageAspectRatio = livePost.imageAspectRatio
        selectedEditPhotoData = nil
        selectedEditPhotoItem = nil
        uploadedEditImageUrl = nil
        uploadedEditAspectRatio = nil
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
                imageAspectRatio: effectiveAspectRatio
            )
            guard succeeded else { return }
            withAnimation(.smooth(duration: 0.4)) { editMode = false }
        }
    }

    func cancelEditing() {
        draftTitle = livePost.title
        draftDescription = livePost.description
        draftTone = livePost.tone
        draftImageUrl = livePost.imageUrl
        draftImageAspectRatio = livePost.imageAspectRatio
        selectedEditPhotoData = nil
        selectedEditPhotoItem = nil
        uploadedEditImageUrl = nil
        uploadedEditAspectRatio = nil
        withAnimation(.smooth(duration: 0.4)) { editMode = false }
    }

    // MARK: - Comment editing

    func beginCommentEditing(commentID: UUID, body: String) {
        replyingToCommentID = nil
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

    func postNewComment() async {
        let trimmed = newCommentDraft.trimmed
        guard !trimmed.isEmpty else { return }
        let succeeded = await store.addComment(postID: livePost.id, body: trimmed, parentCommentID: nil)
        if succeeded {
            newCommentDraft = ""
            isNewCommentFocused = false
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
    }

    func loadAndUploadEditImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              UIImage(data: rawData) != nil else { return }
        selectedEditPhotoData = rawData
        guard let userID = store.currentUserID else { return }
        isUploadingEditImage = true
        defer { isUploadingEditImage = false }
        if let result = await ImageUploader.upload(input: .rawData(rawData), type: .postPhoto, userID: userID) {
            uploadedEditImageUrl = result.url
            uploadedEditAspectRatio = result.aspectRatio
            draftImageUrl = nil
        }
    }
}
