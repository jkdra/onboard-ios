//
//  PhotoAttachmentController.swift
//  On Board
//
//  Shared pick → crop → upload state machine for a single photo attachment.
//  NewPostView, PostDetailView's edit mode, and ProfileView's avatar picker
//  each used to hand-roll the same 6-8 @State vars and load/upload methods,
//  differing only in PhotoType and what happens on upload failure — this is
//  that logic, once.
//

import Foundation
import Observation
import PhotosUI
import SwiftUI

@Observable
@MainActor
final class PhotoAttachmentController {
    let type: PhotoType

    var selectedPhotoItem: PhotosPickerItem?
    var selectedPhotoData: Data?
    var uncroppedImage: UIImage?
    var uploadedURL: String?
    var uploadedAspectRatio: Double?
    var isUploading = false
    /// True after an upload failure, cleared on the next attempt — for callers
    /// that show their own inline "couldn't upload" caption rather than (or in
    /// addition to) `alertError`.
    var uploadFailed = false
    var alertError: PresentableAlertError?

    var hasImage: Bool { selectedPhotoData != nil }

    /// Bumped at the start of every `uploadCropped` call. A cancel-and-retry
    /// (pick photo A, crop, then — before A's upload resolves — pick photo B
    /// and crop that too) starts a second overlapping upload; without this,
    /// whichever network response lands last wins the write to
    /// `uploadedURL`/`uploadedAspectRatio`, which can silently revert the
    /// picture back to the photo the user already replaced.
    private var uploadGeneration = 0

    init(type: PhotoType) {
        self.type = type
    }

    /// Loads the picked item into `uncroppedImage` so the caller can present
    /// its crop sheet. A failure here always alerts — the user just tapped a
    /// specific photo, so a silent no-op reads as "nothing happened," not
    /// "that failed."
    func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: rawData) else {
            alertError = PresentableAlertError(
                message: "Couldn't load that photo",
                recoverySuggestion: "Try a different photo, or make sure it's fully downloaded from iCloud."
            )
            return
        }
        uncroppedImage = uiImage
    }

    /// Uploads the cropped result. `revertPreviewOnFailure` matters because
    /// the three callers differ on what's sensible to show after a failed
    /// upload: a brand-new post composer has no fallback image, so it keeps
    /// showing the failed preview (the caller's own caption explains the post
    /// will go text-only); editing an existing post or a profile photo has a
    /// real previous image to revert to, so the preview drops back to it.
    /// `alertOnFailure` is separate: only the avatar picker pops a modal today
    /// (no visible fallback reads as urgent enough to interrupt); the two post
    /// composers rely on their own inline caption instead.
    func uploadCropped(
        _ image: UIImage,
        userID: UUID,
        revertPreviewOnFailure: Bool,
        alertOnFailure: Bool
    ) async {
        uploadGeneration += 1
        let generation = uploadGeneration

        uploadFailed = false
        isUploading = true
        defer { if generation == uploadGeneration { isUploading = false } }

        // A full-resolution JPEG encode is real main-thread work; ImageUploader
        // already does its own resize/encode off-main for the actual upload
        // below, but this is a second, separate encode purely to back the
        // local preview thumbnail, so it gets the same treatment.
        let previewData = await Task.detached(priority: .userInitiated) {
            image.jpegData(compressionQuality: 0.85)
        }.value
        guard generation == uploadGeneration else { return }
        selectedPhotoData = previewData

        do {
            let result = try await ImageUploader.upload(input: .uiImage(image), type: type, userID: userID)
            guard generation == uploadGeneration else { return }
            uploadedURL = result.url
            uploadedAspectRatio = result.aspectRatio
        } catch {
            guard generation == uploadGeneration else { return }
            uploadedURL = nil
            uploadedAspectRatio = nil
            uploadFailed = true
            if revertPreviewOnFailure {
                selectedPhotoData = nil
                selectedPhotoItem = nil
            }
            if alertOnFailure {
                alertError = PresentableAlertError.from(error)
            }
        }
    }

    /// Clears the attachment entirely — the "✕ remove image" action, not a
    /// failure path.
    func removeImage() {
        selectedPhotoItem = nil
        selectedPhotoData = nil
        uploadedURL = nil
        uploadedAspectRatio = nil
        uploadFailed = false
    }

    /// Full reset, e.g. when re-entering an editor fresh.
    func reset() {
        removeImage()
        uncroppedImage = nil
        isUploading = false
    }
}
