//
//  PostDetailView+Views.swift
//  On Board
//
//  All @ViewBuilder sub-views and toolbar content for PostDetailView.
//

import SwiftUI
import PhotosUI

extension PostDetailView {

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        let livePost = livePost
        if editMode {
            ToolbarItem(placement: .topBarLeading) {
                Button { cancelEditing() } label: {
                    Label("Cancel", systemImage: "xmark").toolbarActionLabel()
                }
            }
            ToolbarItem(placement: .principal) {
                EditingIndicator()
                    .fontStyle(.title3)
                    .fixedSize()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { saveEdits() } label: {
                    Label("Save", systemImage: "checkmark").toolbarActionLabel()
                }
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                TonePicker(selection: $draftTone, showBackground: false)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
        }

        if isReadOnly {
            ToolbarItem(placement: .principal) {
                Label("Archived Post", systemImage: "archivebox")
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }

        if !editMode, !isCommentEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if canEdit && !isReadOnly {
                        Button { beginEditing() } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    ShareLink(item: shareText, subject: Text(livePost.title), message: Text(shareText)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    if !canEdit {
                        Link(destination: reportURL) { Label("Report", systemImage: "flag") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }

        if isCommentEditing {
            ToolbarItem(placement: .bottomBar) {
                Button { confirmCommentEditing() } label: { Label("Save", systemImage: "checkmark") }
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                Button { cancelCommentEditing() } label: { Label("Cancel", systemImage: "xmark") }
            }
        }
    }

    // MARK: - Read mode

    @ViewBuilder
    var postContent: some View {
        let livePost = livePost
        HStack(spacing: 10) {
            NavigationLink(value: BoardRoute.profile(authorProfile)) {
                HStack(spacing: 10) {
                    AvatarView(profile: authorProfile, size: .small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(authorProfile.displayName)
                            .fontStyle(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("@\(authorProfile.handle)")
                            .fontStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .matchedGeometryEffect(id: "postAuthor", in: postNamespace, anchor: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text(livePost.createdAt.boardRelativeAge)
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(livePost.title)
                .fontStyle(.largeTitle)
                .matchedGeometryEffect(id: "postTitle", in: postNamespace, properties: .position, anchor: .leading)
            Text(livePost.description)
                .fontStyle(.body)
                .matchedGeometryEffect(id: "postDescription", in: postNamespace, properties: .position, anchor: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleTapHeart(
            size: 80,
            isEnabled: !isReadOnly,
            isLiked: { store.userReaction(for: livePost.id) == .like },
            onLike: { store.setReaction(postId: livePost.id, reaction: .like) }
        )

        if let urlString = livePost.imageUrl, let url = URL(string: urlString) {
            Button { showImageViewer = true } label: {
                BoardAsyncImage(url: url, tone: tone, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(tone.color.opacity(0.25), lineWidth: 0.9)
                    }
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "postImage", in: postNamespace)
        }
    }

    @ViewBuilder
    var commentsSection: some View {
        let livePost = livePost
        let comments = store.comments(for: livePost.id)
        let commentCount = comments.reduce(0) { $0 + $1.threadCount }
        HStack(spacing: 6) {
            Text("Comments")
                .fontStyle(.title3)
                .foregroundStyle(.primary)
            if commentCount > 0 {
                Text("\(commentCount)")
                    .fontStyle(.title3)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .opacity(isCommentEditing ? 0.32 : 1)

        if !isReadOnly {
            NewCommentComposer(
                draft: $newCommentDraft,
                isFocused: $isNewCommentFocused,
                tone: tone,
                isDisabled: isCommentEditing,
                onPost: postNewComment
            )
        }

        if isLoadingComments && comments.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if comments.isEmpty {
            Text("no comments yet. start the thread.")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(comments) { comment in
                    CommentView(
                        postID: livePost.id,
                        comment: comment,
                        isInteractive: !isReadOnly,
                        editingCommentID: editingCommentID,
                        replyingToCommentID: replyingToCommentID,
                        draftCommentBody: $draftCommentBody,
                        onBeginEdit: beginCommentEditing,
                        onConfirmEdit: confirmCommentEditing,
                        onReply: { commentID in
                            cancelCommentEditing()
                            replyingToCommentID = commentID
                        },
                        onCancelReply: { replyingToCommentID = nil },
                        onDelete: { commentID in
                            commentPendingDeletion = commentID
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    var editImageSection: some View {
        let hasImage = selectedEditPhotoData != nil || draftImageUrl != nil

        if hasImage {
            // ── Image preview with overlaid controls ───────────────────────
            Group {
                if let data = selectedEditPhotoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else if let urlString = draftImageUrl, let url = URL(string: urlString) {
                    BoardAsyncImage(url: url, tone: tone, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Upload dimming overlay
            .overlay {
                if isUploadingEditImage {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.black.opacity(0.45))
                        ProgressView().tint(.white)
                    }
                }
            }
            // Remove button — top-trailing corner
            .overlay(alignment: .topTrailing) {
                Button(role: .destructive) {
                    withAnimation(.smooth(duration: 0.25)) { removeEditImage() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .shadow(color: .black.opacity(0.25), radius: 4)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingEditImage)
                .padding(10)
            }
            // Change photo — bottom-trailing pill
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $selectedEditPhotoItem, matching: .images) {
                    Label("Change", systemImage: "camera.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                }
                .disabled(isUploadingEditImage)
                .padding(10)
            }
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        } else {
            // ── No image — dashed add-photo target ────────────────────────
            PhotosPicker(selection: $selectedEditPhotoItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3)
                    Text("Add a photo")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                }
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }
}

// Total comments in a subtree (a top-level comment plus all nested replies), used for
// the "Comments N" header count.
private extension Comment {
    var threadCount: Int { 1 + replies.reduce(0) { $0 + $1.threadCount } }
}
