//
//  PhotoAttachmentTile.swift
//  On Board
//
//  The tap-to-add-a-photo control shared by NewPostView and PostDetailView's
//  edit mode. Used to be a plain `.boardSecondary` button sitting above a
//  separate preview rectangle — two unrelated elements stacked. This is one
//  tile that morphs between them: a dashed rounded-rect with a circled "+"
//  (borrowing NewPostCard's empty-state language, so "add a photo" reads as
//  the same gesture everywhere it appears) that becomes the actual photo
//  preview once one's picked. Tapping the photo itself reopens the picker to
//  swap it (matching both prior implementations); a small "✕" overlay removes
//  it entirely.
//
//  Not used for the avatar picker — that's already a circular tap-to-change
//  photo, a different (and already reasonable) idiom for a profile picture.
//

import PhotosUI
import SwiftUI

struct PhotoAttachmentTile: View {
    @Bindable var controller: PhotoAttachmentController
    var onCapture: (UIImage) -> Void
    var placeholderTitle: String = "Add a photo"
    /// PostDetailView's edit mode: the post's *existing* image, shown until a
    /// new one is picked this session. NewPostView has no such concept and
    /// leaves this nil.
    var existingImageURL: URL? = nil
    var tone: PostTone = .blue
    /// Overrides what the "✕" does — PostDetailView's edit mode also needs to
    /// clear its own `draftImageUrl` (the existing photo), since otherwise
    /// `existingImageURL` would keep the tile showing it right after removal.
    /// Defaults to just clearing the controller, which is all NewPostView needs.
    var onRemove: (() -> Void)? = nil

    private let cornerRadius: CGFloat = 18

    private var hasImage: Bool { controller.hasImage || existingImageURL != nil }

    var body: some View {
        Group {
            if hasImage {
                filledTile
            } else {
                emptyTile
            }
        }
        .animation(.smooth(duration: 0.3), value: hasImage)
    }

    private var emptyTile: some View {
        PhotoSourceButton(selection: $controller.selectedPhotoItem, onCapture: onCapture) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "photo.badge.plus")
                        .fontStyle(.title3)
                        .foregroundStyle(.secondary)
                }
                Text(placeholderTitle)
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10]))
                .foregroundStyle(.secondary.opacity(0.4))
        }
    }

    @ViewBuilder
    private var filledTile: some View {
        // Tapping the photo reopens the picker to swap it — the whole tile is
        // the "change" affordance, not a separate labeled button beside it.
        PhotoSourceButton(selection: $controller.selectedPhotoItem, onCapture: onCapture) {
            Group {
                if let data = controller.selectedPhotoData, let uiImage = PhotoPreviewCache.image(for: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else if let existingImageURL {
                    BoardAsyncImage(url: existingImageURL, tone: tone, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
            .overlay {
                if controller.isUploading {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(controller.isUploading)
        .overlay(alignment: .topTrailing) {
            if !controller.isUploading {
                Button {
                    if let onRemove { onRemove() } else { controller.removeImage() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .fontStyle(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .shadow(color: .black.opacity(0.25), radius: 4)
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Remove image")
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}
