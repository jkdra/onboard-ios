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
        if editMode {
            EditModeToolbarItems(
                saveTint: draftTone.color,
                onCancel: cancelEditing,
                onSave: saveEdits
            )
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
                    ShareLink(item: shareURL, subject: Text(livePost.title)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    if !isOwnPost {
                        Button {
                            reportTarget = .post(livePost)
                        } label: {
                            Label("Report Post", systemImage: "flag")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").fontWeight(.semibold)
                }
            }
        }

        if isCommentEditing {
            ToolbarItem(placement: .bottomBar) {
                Button { confirmCommentEditing() } label: { Label("Save", systemImage: "checkmark").fontWeight(.semibold) }
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                Button { cancelCommentEditing() } label: { Label("Cancel", systemImage: "xmark").fontWeight(.semibold) }
            }
        }
    }

    // MARK: - Read mode

    @ViewBuilder
    var postContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            authorRow
            restOfPostContent
        }
    }
    
    @ViewBuilder
    private var authorRow: some View {
        HStack(spacing: 10) {
            // Compare against the post's own authorId, NOT authorProfile.id.
            // authorProfile comes from `store.profile(forAuthor:)`, which falls
            // back to `Profile(handle:displayName:)` — defaulting `id` to a
            // fresh `UUID()` — whenever the author isn't in the local profile
            // cache. That fake id never equals originatingProfileID, so viewing
            // your own (uncached) posts from your own profile page mistakenly
            // took the NavigationLink branch below: the "double push" bug —
            // tapping into a post, then its author row pushing a second, bogus
            // copy of the very profile you were already on.
            if originatingProfileID == livePost.authorId {
                Button {
                    dismiss()
                } label: {
                    authorLabel
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: BoardRoute.profile(authorProfile)) {
                    authorLabel
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var authorLabel: some View {
        HStack(spacing: 10) {
            AvatarView(profile: authorProfile, size: .small)
            VStack(alignment: .leading, spacing: 1) {
                Text(authorProfile.handle)
                    .fontStyle(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(livePost.createdAt.boardRelativeAge)
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .matchedGeometryEffect(id: "postAuthor", in: postNamespace, anchor: .leading)
    }

    @ViewBuilder
    private var restOfPostContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(livePost.title)
                .fontStyle(.largeTitle)
                // matchedGeometryEffect with properties: .position (no .size) can still
                // leave Text trusting a stale cached frame from the transition, wrapping
                // it to one line until the next layout pass. fixedSize forces it to always
                // measure its own natural multiline height instead.
                .fixedSize(horizontal: false, vertical: true)
                .matchedGeometryEffect(id: "postTitle", in: postNamespace, properties: .position, anchor: .leading)
            Text(livePost.description)
                .fontStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
                .matchedGeometryEffect(id: "postDescription", in: postNamespace, properties: .position, anchor: .leading)
                
            if !livePost.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(livePost.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .fontStyle(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleTapHeart(
            size: 80,
            isEnabled: !isReadOnly,
            isLiked: { store.userReaction(for: livePost.id) == .like },
            onLike: { store.setReaction(postId: livePost.id, reaction: .like) }
        )

        if let urlString = livePost.imageUrl, let url = URL(string: urlString) {
            BoardAsyncImage(url: url, tone: tone, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tone.color.opacity(0.25), lineWidth: 0.9)
                }
                .matchedTransitionSource(id: "postImage", in: postNamespace)
                .doubleTapHeart(
                    size: 80,
                    isEnabled: !isReadOnly,
                    isLiked: { store.userReaction(for: livePost.id) == .like },
                    onLike: { store.setReaction(postId: livePost.id, reaction: .like) },
                    onSingleTap: { showImageViewer = true }
                )
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

        if isLoadingComments && comments.isEmpty {
            // Ghost comment rows (avatar + handle + two body lines) rather than a
            // bare spinner, so first-load reads as "arriving". Warm visits skip
            // this entirely — comments are cached in the envelope.
            VStack(alignment: .leading, spacing: 18) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 10) {
                        SkeletonShape(shape: Circle())
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 7) {
                            SkeletonShape.line.frame(width: 110, height: 9)
                            SkeletonShape.line.frame(height: 9)
                            SkeletonShape.line.frame(width: 200, height: 9)
                        }
                        .padding(.top, 2)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.vertical, 8)
            .transition(.opacity)
            .accessibilityElement()
            .accessibilityLabel("Loading comments")
        } else if comments.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary.opacity(0.5))
                
                VStack(spacing: 6) {
                    Text(isReadOnly ? "No comments." : "No comments yet.")
                        .fontStyle(.headline)
                        .foregroundStyle(.primary)
                    if !isReadOnly {
                        Text("Be the first to start the thread.")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !isReadOnly {
                    Button {
                        withAnimation(.smooth(duration: 0.35)) {
                            composer.beginNewComment()
                        }
                    } label: {
                        Text("Add Comment")
                            .fontStyle(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .background(Capsule(style: .continuous).fill(tone.color.opacity(0.15)))
                    .foregroundStyle(tone.color)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 32)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(comments) { comment in
                    CommentView(
                        postID: livePost.id,
                        comment: comment,
                        tone: tone,
                        isInteractive: !isReadOnly,
                        editingCommentID: editingCommentID,
                        replyTargetID: composer.target?.replyParentID,
                        draftCommentBody: $draftCommentBody,
                        onBeginEdit: beginCommentEditing,
                        onConfirmEdit: confirmCommentEditing,
                        onReply: { comment in
                            cancelCommentEditing()
                            withAnimation(.smooth(duration: 0.35)) {
                                composer.beginReply(parentID: comment.id, handle: comment.author)
                            }
                        },
                        onDelete: { commentID in
                            commentPendingDeletion = commentID
                        },
                        onReport: { comment in
                            reportTarget = .comment(comment, postID: livePost.id)
                        },
                        onBlockAuthor: { comment in
                            guard let authorID = comment.authorId else { return }
                            blockCandidate = BlockCandidate(userID: authorID, handle: comment.author)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Edit mode

    /// Glass-field WYSIWYG editor — renders into the same matched-geometry
    /// slots as the read-mode text, so entering edit mode morphs in place.
    @ViewBuilder
    var postEditContent: some View {
        // Panels occupy real space, so the outer VStack's 16pt spacing is the
        // true visible rhythm — no inner stack needed.
        TextField("Title", text: $draftTitle, axis: .vertical)
            .textFieldStyle(.boardTitle)
            .fixedSize(horizontal: false, vertical: true)
            .fontStyle(.largeTitle)
            .keyboardType(.default)
            .textInputAutocapitalization(.sentences)
            .matchedFieldText(id: "postTitle", in: postNamespace, variant: .title)
        TextField("Description", text: $draftDescription, axis: .vertical)
            .textFieldStyle(.boardBody)
            // Multi-line fields re-measure a beat after appearing; without
            // this they settle unanimated mid-morph. Mirrors read mode's
            // fixedSize note above.
            .fixedSize(horizontal: false, vertical: true)
            .fontStyle(.body)
            .keyboardType(.twitter)
            .matchedFieldText(id: "postDescription", in: postNamespace, variant: .body)

        editTagsSection

        editImageSection
            .transition(.opacity)
    }

    @ViewBuilder
    var editTagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tags (\(draftTags.count)/3)", systemImage: "number")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(draftTags.isEmpty ? "Add Tags" : "Edit") {
                    showingTagSelection = true
                }
                .fontStyle(.subheadline)
            }
            
            if !draftTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draftTags, id: \.self) { tag in
                            Text("#\(tag)")
                                .fontStyle(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    var editImageSection: some View {
        let hasImage = selectedEditPhotoData != nil || draftImageUrl != nil

        if editImageUploadFailed {
            Label("Image couldn't be uploaded — the previous one is kept.", systemImage: "exclamationmark.triangle")
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
        }

        if hasImage {
            // ── Image preview with overlaid controls ───────────────────────
            Group {
                if let data = selectedEditPhotoData, let uiImage = PhotoPreviewCache.image(for: data) {
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
                        .fontStyle(.title2)
                        .fontWeight(.medium)
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
                        .font(.caption.weight(.medium))
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
