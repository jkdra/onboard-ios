//
//  CommentComposerBar.swift
//  On Board
//
//  Two-state bottom bar for PostDetailView. Browse: the reaction pill cluster
//  plus a circular Comment button. Compose: a glass composer (reply context
//  chip, multiline field, tone-colored send) replacing the whole bar. The two
//  states never coexist, so the composer can never collide with the reaction
//  pills above the keyboard. Browse and compose simply crossfade — no shared
//  morph identity between the button and the field.
//

import SwiftUI

struct CommentComposerBar: View {
    let tone: PostTone
    let counts: [Reaction: Int]
    @Binding var selectedReaction: Reaction?
    @Binding var composer: CommentComposerState
    var isReadOnly: Bool
    var isRecord: Bool
    let onPost: () async -> Void
    let onExpand: () -> Void
    /// Set by the parent while `CommentComposerSheet` is presented. Presenting
    /// a sheet resigns this bar's first responder, which would otherwise read
    /// as a cancel via the focus-loss handler below and wipe the draft/target
    /// the sheet is about to show.
    var isSheetPresented: Bool = false
    /// Set by the parent while the post-failure alert is presented. Presenting
    /// the alert resigns this bar's first responder just like the sheet does,
    /// which would otherwise read as a cancel via the focus-loss handler below
    /// and silently discard the reply target after a failed post.
    var isErrorPresented: Bool = false

    @FocusState private var isFieldFocused: Bool
    // Guards against a second submit while the first is in flight (ported from
    // NewCommentComposer) — the network round-trip leaves the button live.
    @State private var isPosting = false
    // Tracked via onGeometryChange; compared against a Dynamic-Type-scaled
    // ceiling to decide when the field has wrapped and Expand appears.
    @State private var fieldHeight: CGFloat = 0
    // A single subheadline line is ~20pt at default text size; this scales
    // with the user's text size so large accessibility sizes don't make an
    // unwrapped single line spuriously exceed the ceiling.
    @ScaledMetric(relativeTo: .subheadline) private var singleLineCeiling: CGFloat = 34
    // 2 lines of subheadline is roughly ~54pt.
    @ScaledMetric(relativeTo: .subheadline) private var twoLineCeiling: CGFloat = 54

    private var trimmedEmpty: Bool { composer.draft.trimmed.isEmpty }
    private var morphAnimation: Animation { .smooth(duration: 0.35) }
    private var isMultiline: Bool { fieldHeight > singleLineCeiling }
    private var showExpandButton: Bool { fieldHeight > twoLineCeiling }

    var body: some View {
        Group {
            content
        }
        .safeAreaPadding()
        .background(barBackground)
        .animation(morphAnimation, value: composer.isComposing)
        .onChange(of: composer.isComposing) { _, composing in
            isFieldFocused = composing
        }
        .onChange(of: isFieldFocused) { _, focused in
            // Keyboard dismissal (interactive swipe / Done) exits compose.
            // Guard the posting window, where focus can drop without the user
            // cancelling.
            if !focused && composer.isComposing && !isPosting && !isSheetPresented && !isErrorPresented {
                withAnimation(morphAnimation) { composer.dismiss() }
            }
        }
        .onChange(of: isSheetPresented) { _, presented in
            // Dismissing the sheet (chevron-down) should return focus to the
            // inline field with the draft intact, per spec. A successful post
            // already dropped composer.isComposing to false by the time the
            // sheet dismisses itself, so this only fires on a manual collapse.
            if !presented && composer.isComposing {
                isFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if composer.isComposing {
            composeLayout
        } else {
            browseLayout
        }
    }

    // MARK: - Browse state

    private var browseLayout: some View {
        HStack(spacing: 8) {
            ReactionBar(
                counts: counts,
                tone: tone,
                selected: $selectedReaction,
                isInteractive: !isReadOnly,
                isRecord: isRecord
            )

            if !isReadOnly {
                commentButton
            }
        }
        .transition(.opacity)
    }

    private var commentButton: some View {
        Button {
            withAnimation(morphAnimation) { composer.beginNewComment() }
        } label: {
            Image(systemName: "plus.bubble.fill")
                .fontStyle(.callout)
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .background(glassBackground(shape: AnyShape(Circle())))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a comment")
    }

    // MARK: - Compose state

    private var composeLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .reply(_, let handle) = composer.target {
                replyChip(handle: handle)
            }

            HStack(alignment: .bottom, spacing: 8) {
                closeButton
                fieldCluster
            }
        }
        .transition(.opacity)
    }

    /// ✕ lives alone at the leading edge, outside the field — cancelling is
    /// always one obvious tap in a fixed spot. Independent glass circle, not
    /// tied to ReactionBar's frame: the reaction pills already paint their
    /// own material (ReactionBar.reactionBackground), so sharing an identity
    /// here would stack a second full-width glass tray behind them.
    private var closeButton: some View {
        Button {
            withAnimation(morphAnimation) { composer.dismiss() }
        } label: {
            Image(systemName: "xmark")
                .fontStyle(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .background(glassBackground(shape: AnyShape(Circle())))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel comment")
    }

    /// The glass field owns the text plus a trailing action column pinned to
    /// its bottom corner: send at the bottom, Expand directly above it once
    /// the text wraps. Neither moves as the field grows.
    private var fieldCluster: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                composer.target?.isReply == true ? "Write a reply…" : "Add a comment…",
                text: $composer.draft,
                axis: .vertical
            )
            .fontStyle(.subheadline)
            .keyboardType(.twitter)
            .lineLimit(1...5)
            .focused($isFieldFocused)
            .disabled(isPosting)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                fieldHeight = height
            }
            .padding(.vertical, 6)
            .onChange(of: composer.draft) { _, newValue in
                if newValue.count > 280 {
                    composer.draft = String(newValue.prefix(280))
                }
            }

            VStack(spacing: 6) {
                if showExpandButton {
                    expandButton
                        .transition(.opacity.combined(with: .scale))
                }

                sendButton
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(glassBackground(shape: AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))))
        .animation(.smooth(duration: 0.2), value: isMultiline)
        // highPriorityGesture, not .gesture: the TextField underneath owns its
        // own pan/selection recognizers, which win arbitration over a plain
        // .gesture() attached here — a swipe starting on the text itself
        // (i.e. anywhere but the thin edge padding) would otherwise almost
        // never reach this handler. highPriorityGesture only claims the
        // touch once the drag clears minimumDistance, so taps/typing/cursor
        // placement are unaffected.
        .highPriorityGesture(
            DragGesture(minimumDistance: 15, coordinateSpace: .local)
                .onEnded { value in
                    // Only trigger on clear upward swipes
                    if value.translation.height < -20 && abs(value.translation.width) < 40 {
                        onExpand()
                    }
                }
        )
    }

    private var expandButton: some View {
        Button(action: onExpand) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isPosting)
        .accessibilityLabel("Expand composer")
    }

    private var sendButton: some View {
        Button {
            Task {
                isPosting = true
                await onPost()
                isPosting = false
            }
        } label: {
            if isPosting {
                ProgressView()
                    .scaleEffect(0.9)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(trimmedEmpty ? Color.secondary.opacity(0.4) : tone.color)
                    .frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.plain)
        .disabled(trimmedEmpty || isPosting)
        .accessibilityLabel("Post comment")
    }

    private func replyChip(handle: String) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .fontStyle(.caption2)
                Text("Replying to \(handle)")
                    .fontStyle(.caption)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)

            Button {
                withAnimation(.smooth(duration: 0.25)) { composer.clearReplyTarget() }
            } label: {
                Image(systemName: "xmark")
                    .fontStyle(.caption2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop replying")
        }
        .foregroundStyle(.primary)
        .background {
            GlassBackground(shape: Capsule(style: .continuous), interactive: true)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Materials

    private func glassBackground(shape: AnyShape) -> some View {
        GlassBackground(
            shape: shape,
            interactive: true,
            fallback: AnyShapeStyle(Color(.systemBackground).opacity(0.45))
        )
    }

    @ViewBuilder
    private var barBackground: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            Rectangle().fill(.bar)
                .ignoresSafeArea()
        }
    }
}

#Preview("Browse") {
    @Previewable @State var composer = CommentComposerState()
    @Previewable @State var reaction: Reaction? = nil
    CommentComposerBar(
        tone: .green,
        counts: [:],
        selectedReaction: $reaction,
        composer: $composer,
        isReadOnly: false,
        isRecord: false,
        onPost: {},
        onExpand: {}
    )
}
