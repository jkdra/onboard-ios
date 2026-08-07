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
                canSave: !isSavingEdits,
                saveTint: draftTone.color,
                onCancel: cancelEditing,
                onSave: saveEdits
            )
        }

        if editMode {
            // Same principal-slot reasoning as NewPostView: tone is a
            // POST property, so it lives in post-level chrome — not beside
            // the text buttons, and not under the keyboard in a bottomBar.
            ToolbarItem(placement: .principal) {
                TonePicker(selection: $draftTone, showBackground: false)
            }
        } else if isReadOnly {
            ToolbarItem(placement: .principal) {
                Label("Archived Post", systemImage: "archivebox")
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        } else if let weekEnd = clearingSoonWeekEnd {
            // Clears-soon: a live ticking countdown rides the nav bar's principal
            // slot instead of a separate top banner. Mutually exclusive with the
            // archived principal above (a live post is never read-only).
            ToolbarItem(placement: .principal) {
                ClearingSoonPrincipal(weekEnd: weekEnd)
            }
        }

        if showImageViewer, imageViewerScale <= 1.0 {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                        showImageViewer = false
                    }
                } label: {
                    Label("Close", systemImage: "xmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }

        if !editMode, !isCommentEditing, !showImageViewer {
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
                    ShareLink(item: shareURL, subject: Text(livePost.previewLine)) {
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
                        .accessibilityLabel("Post options")
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
            // Rendered markup (titles, bold, bullets…) — PostMarkupView already
            // applies fixedSize per block (see the old note about
            // matchedGeometryEffect leaving Text with a stale cached frame).
            PostMarkupView(content: livePost.content)
                .matchedGeometryEffect(id: "postContent", in: postNamespace, properties: .position, anchor: .topLeading)
                
            // Tag chips are gone from detail on purpose: tags are inline
            // hashtags in the content now, highlighted right where they were
            // typed. (Cards keep their chips row — a truncated card can cut
            // off a trailing hashtag line, so chips guarantee visibility.)
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
                // Reserve the photo's real aspect ratio up front so the
                // "signal lost" placeholder occupies the same box the loaded
                // image will — no height jump when it finishes. Older posts
                // may lack the ratio (nil) → fall back to self-sizing.
                .aspectRatio(livePost.imageAspectRatio.map { CGFloat($0) }, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tone.color.opacity(0.25), lineWidth: 0.9)
                }
                .background {
                    Color.clear.matchedGeometryEffect(id: "postImage", in: postNamespace)
                }
                .opacity(showImageViewer ? 0 : 1)
                .doubleTapHeart(
                    size: 80,
                    isEnabled: !isReadOnly,
                    isLiked: { store.userReaction(for: livePost.id) == .like },
                    onLike: { store.setReaction(postId: livePost.id, reaction: .like) },
                    onSingleTap: { withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) { showImageViewer = true } }
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
                        editingCommentID: commentEdit.editingCommentID,
                        replyTargetID: composer.target?.replyParentID,
                        draftCommentBody: $commentEdit.draftCommentBody,
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
        // The same rich composer as NewPostView: markers dim in place, and the
        // formatting bar comes with it as the field's own keyboard accessory —
        // nothing for this screen to place or gate.
        MarkupTextEditor(text: $draftContent, controller: editEditorController)
            .padding(14)
            .background {
                GlassBackground(shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                                fallback: AnyShapeStyle(.thinMaterial))
            }
            .matchedFieldText(id: "postContent", in: postNamespace, variant: .body)

        editImageSection
            .transition(.opacity)
    }

    @ViewBuilder
    var editImageSection: some View {
        if editPhoto.uploadFailed {
            Label("Image couldn't be uploaded — the previous one is kept.", systemImage: "exclamationmark.triangle")
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
        }

        if photoAttachmentsEnabled {
            PhotoAttachmentTile(
                controller: editPhoto,
                onCapture: { editPhoto.uncroppedImage = $0 },
                existingImageURL: draftImageUrl.flatMap(URL.init(string:)),
                tone: tone,
                onRemove: { withAnimation(.smooth(duration: 0.25)) { removeEditImage() } }
            )
        }
    }
}
