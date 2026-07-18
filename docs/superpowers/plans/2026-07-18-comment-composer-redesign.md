# Comment Composer & Thread Interaction Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace PostDetailView's three comment-entry mechanisms with a two-state bottom bar (reaction pills + circular Comment button ⇄ glass composer with reply chip), and make reply threads collapsible via tone-tinted tappable thread lines.

**Architecture:** A pure-value `CommentComposerState` state machine (unit-tested) drives a new `CommentComposerBar` view that replaces `PostActionBar` in the bottom `safeAreaInset`. The top `NewCommentComposer` box and `CommentView`'s inline reply composer are deleted; replies target the shared composer. `CommentView` gains a tone parameter, a collapsible subtree, and a capsule thread line. No `BoardStore` changes.

**Tech Stack:** SwiftUI (iOS 18 floor, iOS 26 `glassEffect`/`GlassEffectContainer` behind `#available` guards), Swift Testing (`@Test`/`#expect`, NOT XCTest).

**Spec:** `docs/superpowers/specs/2026-07-18-comment-composer-redesign-design.md`

## Global Constraints

- Paths contain spaces — always quote (`"On Board/Views/..."`) in shell commands.
- The Xcode project uses file-system-synchronized groups: creating/deleting `.swift` files on disk is sufficient; never edit `project.pbxproj`.
- Build check: `cd "/Users/jawadkhadra/On Board/onboard-ios" && xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
- Test run: `xcodebuild test -scheme "On Board" -destination "id=59A3B7F5-9F3A-4492-B70D-72CF75B884C9" -only-testing "On BoardTests" -parallel-testing-enabled NO` — if that UDID is gone, pick an iPhone from `xcrun simctl list devices available`. Swift Testing summary line looks like `✔ Test run with N tests in M suites passed`; the XCTest "Executed 0 tests" line is expected noise.
- Haptics: only via `.sensoryFeedback`, always gated on `@AppStorage("hapticsEnabled")`. Never `UIImpactFeedbackGenerator`.
- iOS 26 material code must have a pre-26 fallback (`Color(.systemBackground).opacity(0.45)` fills / `Rectangle().fill(.bar)` bars — copy `ReactionBar`/`PostActionBar`'s existing pattern).
- Font sizing goes through the project's `.fontStyle(_:)` modifier, not `.font(_:)`.
- Commit after every task. Working tree contains a large uncommitted polish pass — `git add` ONLY the files your task touches; never `git add -A`.

---

### Task 1: CommentComposerState model (TDD)

**Files:**
- Create: `On Board/Views/Post/CommentComposerState.swift`
- Test: `On BoardTests/CommentComposerStateTests.swift`

**Interfaces:**
- Consumes: `String.trimmed` (existing extension in the app target).
- Produces: `enum ComposerTarget: Equatable { case newComment; case reply(parentID: UUID, handle: String) }` with `var isReply: Bool`, `var replyParentID: UUID?`; `struct CommentComposerState: Equatable` with `private(set) var target: ComposerTarget?`, `var draft: String`, `var isComposing: Bool`, and mutating funcs `beginNewComment()`, `beginReply(parentID:handle:)`, `clearReplyTarget()`, `dismiss()`, `finishPosting()`. Tasks 3–4 depend on these exact names.

- [ ] **Step 1: Write the failing test**

Check the `@testable import` line at the top of `On BoardTests/On_BoardTests.swift` and use the same module name (expected: `On_Board`). Create `On BoardTests/CommentComposerStateTests.swift`:

```swift
//
//  CommentComposerStateTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct CommentComposerStateTests {
    private let parentID = UUID()

    @Test func startsInBrowseState() {
        let state = CommentComposerState()
        #expect(!state.isComposing)
        #expect(state.target == nil)
    }

    @Test func switchingTargetKeepsDraft() {
        var state = CommentComposerState()
        state.beginNewComment()
        state.draft = "half-written thought"
        state.beginReply(parentID: parentID, handle: "sarah")
        #expect(state.draft == "half-written thought")
        #expect(state.target == .reply(parentID: parentID, handle: "sarah"))
    }

    @Test func clearReplyTargetFallsBackToNewComment() {
        var state = CommentComposerState()
        state.beginReply(parentID: parentID, handle: "sarah")
        state.clearReplyTarget()
        #expect(state.target == .newComment)
        #expect(state.isComposing)
    }

    @Test func clearReplyTargetWhileBrowsingStaysBrowsing() {
        var state = CommentComposerState()
        state.clearReplyTarget()
        #expect(state.target == nil)
    }

    @Test func dismissRetainsNonEmptyDraft() {
        var state = CommentComposerState()
        state.beginNewComment()
        state.draft = "keep me"
        state.dismiss()
        #expect(!state.isComposing)
        #expect(state.draft == "keep me")
    }

    @Test func dismissClearsWhitespaceOnlyDraft() {
        var state = CommentComposerState()
        state.beginNewComment()
        state.draft = "   \n"
        state.dismiss()
        #expect(state.draft.isEmpty)
    }

    @Test func finishPostingClearsEverything() {
        var state = CommentComposerState()
        state.beginReply(parentID: parentID, handle: "sarah")
        state.draft = "posted!"
        state.finishPosting()
        #expect(state.target == nil)
        #expect(state.draft.isEmpty)
    }

    @Test func replyParentIDExtractsOnlyFromReplies() {
        var state = CommentComposerState()
        state.beginNewComment()
        #expect(state.target?.replyParentID == nil)
        state.beginReply(parentID: parentID, handle: "sarah")
        #expect(state.target?.replyParentID == parentID)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/jawadkhadra/On Board/onboard-ios" && xcodebuild test -scheme "On Board" -destination "id=59A3B7F5-9F3A-4492-B70D-72CF75B884C9" -only-testing "On BoardTests/CommentComposerStateTests" -parallel-testing-enabled NO 2>&1 | grep -E "error:|Test run|\*\* TEST"`
Expected: FAIL — compile error `cannot find 'CommentComposerState' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `On Board/Views/Post/CommentComposerState.swift`:

```swift
//
//  CommentComposerState.swift
//  On Board
//
//  State machine for PostDetailView's bottom comment composer. Pure value
//  type so target/draft transitions are unit-testable without SwiftUI.
//

import Foundation

enum ComposerTarget: Equatable {
    case newComment
    case reply(parentID: UUID, handle: String)

    var isReply: Bool {
        if case .reply = self { return true }
        return false
    }

    var replyParentID: UUID? {
        if case .reply(let parentID, _) = self { return parentID }
        return nil
    }
}

struct CommentComposerState: Equatable {
    private(set) var target: ComposerTarget?
    var draft: String = ""

    var isComposing: Bool { target != nil }

    mutating func beginNewComment() {
        target = .newComment
    }

    mutating func beginReply(parentID: UUID, handle: String) {
        target = .reply(parentID: parentID, handle: handle)
    }

    /// Reply chip ✕: keep composing, but as a top-level comment.
    mutating func clearReplyTarget() {
        if target?.isReply == true { target = .newComment }
    }

    /// Composer ✕ / keyboard dismiss: back to browse. A non-empty draft
    /// survives for the session so an accidental dismiss never loses writing.
    mutating func dismiss() {
        target = nil
        if draft.trimmed.isEmpty { draft = "" }
    }

    /// Successful post: back to browse with a clean slate.
    mutating func finishPosting() {
        target = nil
        draft = ""
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: `✔ Test run with 8 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/jawadkhadra/On Board/onboard-ios"
git add "On Board/Views/Post/CommentComposerState.swift" "On BoardTests/CommentComposerStateTests.swift"
git commit -m "Add CommentComposerState machine for the unified comment composer"
```

---

### Task 2: Promote threadCount to the Comment model (TDD)

**Files:**
- Modify: `On Board/Models/Comment.swift` (append extension)
- Modify: `On Board/Views/Post/PostDetailView+Views.swift:416-420` (delete private extension)
- Test: `On BoardTests/CommentThreadCountTests.swift`

**Interfaces:**
- Produces: `Comment.threadCount: Int` (internal — self + all nested replies). Task 5's collapsed pill uses `comment.threadCount - 1`; `PostDetailView+Views.swift:197` keeps using it for the header count.

- [ ] **Step 1: Write the failing test**

The current `threadCount` is `private extension Comment` inside `PostDetailView+Views.swift` — invisible to tests and to `CommentView`. Create `On BoardTests/CommentThreadCountTests.swift` (same `@testable import` as Task 1):

```swift
//
//  CommentThreadCountTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct CommentThreadCountTests {
    @Test func leafCountsItself() {
        let leaf = Comment(author: "a", body: "leaf")
        #expect(leaf.threadCount == 1)
    }

    @Test func threadCountIncludesAllDescendants() {
        let grandchildA = Comment(author: "c", body: "gc-a")
        let grandchildB = Comment(author: "d", body: "gc-b")
        let childWithKids = Comment(author: "b", body: "child", replies: [grandchildA, grandchildB])
        let childLeaf = Comment(author: "e", body: "leaf child")
        let root = Comment(author: "a", body: "root", replies: [childWithKids, childLeaf])

        #expect(root.threadCount == 5)
        // The "Show N replies" pill shows descendants only:
        #expect(root.threadCount - 1 == 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/jawadkhadra/On Board/onboard-ios" && xcodebuild test -scheme "On Board" -destination "id=59A3B7F5-9F3A-4492-B70D-72CF75B884C9" -only-testing "On BoardTests/CommentThreadCountTests" -parallel-testing-enabled NO 2>&1 | grep -E "error:|Test run|\*\* TEST"`
Expected: FAIL — `'threadCount' is inaccessible due to 'private' protection level` (or not found).

- [ ] **Step 3: Move the extension**

Append to `On Board/Models/Comment.swift` (below the existing `Array where Element == Comment` extension):

```swift
extension Comment {
    /// Total comments in this subtree — self plus all nested replies. Drives
    /// the "Comments N" header count and the collapsed-thread "Show N replies"
    /// pill (which subtracts 1 to show descendants only).
    var threadCount: Int { 1 + replies.reduce(0) { $0 + $1.threadCount } }
}
```

Delete from `On Board/Views/Post/PostDetailView+Views.swift` (lines 416–420):

```swift
// Total comments in a subtree (a top-level comment plus all nested replies), used for
// the "Comments N" header count.
private extension Comment {
    var threadCount: Int { 1 + replies.reduce(0) { $0 + $1.threadCount } }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: `✔ Test run with 2 tests in 1 suite passed`. Then run the build check from Global Constraints to confirm `PostDetailView+Views.swift:197` still compiles against the moved extension. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/jawadkhadra/On Board/onboard-ios"
git add "On Board/Models/Comment.swift" "On Board/Views/Post/PostDetailView+Views.swift" "On BoardTests/CommentThreadCountTests.swift"
git commit -m "Promote Comment.threadCount from view-private to model scope"
```

---

### Task 3: CommentComposerBar view

**Files:**
- Create: `On Board/Views/Post/CommentComposerBar.swift`

**Interfaces:**
- Consumes: `CommentComposerState`/`ComposerTarget` (Task 1), existing `ReactionBar`, `PostTone`, `Reaction`, `String.trimmed`, `.fontStyle(_:)`.
- Produces: `CommentComposerBar(tone:counts:selectedReaction:composer:isReadOnly:isRecord:onPost:)` — Task 4 mounts this in the bottom `safeAreaInset`, replacing `PostActionBar`.

- [ ] **Step 1: Create the view**

Create `On Board/Views/Post/CommentComposerBar.swift`:

```swift
//
//  CommentComposerBar.swift
//  On Board
//
//  Two-state bottom bar for PostDetailView. Browse: the reaction pill cluster
//  plus a circular Comment button. Compose: a glass composer (reply context
//  chip, multiline field, tone-colored send) replacing the whole bar. The two
//  states never coexist, so the composer can never collide with the reaction
//  pills above the keyboard. On iOS 26 the circle and the field share a
//  glassEffectID, so the button visibly blooms into the composer; pre-26 the
//  same pairing runs through matchedGeometryEffect over plain fills.
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

    @FocusState private var isFieldFocused: Bool
    @Namespace private var morphNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Guards against a second submit while the first is in flight (ported from
    // NewCommentComposer) — the network round-trip leaves the button live.
    @State private var isPosting = false

    private var trimmedEmpty: Bool { composer.draft.trimmed.isEmpty }
    private var morphAnimation: Animation { .smooth(duration: 0.35) }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer { content }
            } else {
                content
            }
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
            if !focused && composer.isComposing && !isPosting {
                withAnimation(morphAnimation) { composer.dismiss() }
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
                .frame(width: 52, height: 52)
                .contentShape(Circle())
                .background(morphSource(shape: Circle()))
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

                Button {
                    withAnimation(morphAnimation) { composer.dismiss() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .fontStyle(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close composer")

                Button {
                    Task {
                        isPosting = true
                        await onPost()
                        isPosting = false
                    }
                } label: {
                    if isPosting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .fontStyle(.title2)
                            .foregroundStyle(trimmedEmpty ? Color.secondary.opacity(0.4) : tone.color)
                    }
                }
                .buttonStyle(.plain)
                .disabled(trimmedEmpty || isPosting)
                .accessibilityLabel("Post comment")
            }
            .padding(12)
            .background(morphSource(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
        }
        .transition(.opacity)
    }

    private func replyChip(handle: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .fontStyle(.caption2)
            Text("Replying to @\(handle)")
                .fontStyle(.caption)
                .lineLimit(1)
            Button {
                withAnimation(.smooth(duration: 0.25)) { composer.clearReplyTarget() }
            } label: {
                Image(systemName: "xmark")
                    .fontStyle(.caption2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop replying")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill(tone.color.opacity(0.14)))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Materials

    /// Shared morph identity between the circle button and the composer field.
    /// Under Reduce Motion the identity is dropped so the states plainly
    /// crossfade (the .transition(.opacity) on each layout) with no shape morph.
    @ViewBuilder
    private func morphSource(shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            if reduceMotion {
                Color.clear.glassEffect(.regular.interactive(), in: shape)
            } else {
                Color.clear
                    .glassEffect(.regular.interactive(), in: shape)
                    .glassEffectID("composerMorph", in: morphNamespace)
            }
        } else {
            if reduceMotion {
                shape.fill(Color(.systemBackground).opacity(0.45))
            } else {
                shape
                    .fill(Color(.systemBackground).opacity(0.45))
                    .matchedGeometryEffect(id: "composerMorph", in: morphNamespace)
            }
        }
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
        onPost: {}
    )
}
```

- [ ] **Step 2: Build**

Run the build check from Global Constraints. Expected: `** BUILD SUCCEEDED **`. (If `GlassEffectContainer { content }` fails to infer, use `GlassEffectContainer(spacing: 8) { content }` — same behavior.)

- [ ] **Step 3: Commit**

```bash
cd "/Users/jawadkhadra/On Board/onboard-ios"
git add "On Board/Views/Post/CommentComposerBar.swift"
git commit -m "Add two-state CommentComposerBar (reactions + circle button ⇄ glass composer)"
```

---

### Task 4: Wire the bar into PostDetailView; delete the old composers

**Files:**
- Modify: `On Board/Views/Post/PostDetailView.swift` (state block ~lines 26-31, body wrap, safeAreaInset ~149-159)
- Modify: `On Board/Views/Post/PostDetailView+Logic.swift:95-129`
- Modify: `On Board/Views/Post/PostDetailView+Views.swift` (~lines 212-260)
- Modify: `On Board/Views/Post/CommentView.swift` (remove reply composer, rewire params)
- Delete: `On Board/Views/Post/NewCommentComposer.swift`, `On Board/Views/Post/PostActionBar.swift`

**Interfaces:**
- Consumes: `CommentComposerBar` (Task 3), `CommentComposerState` (Task 1).
- Produces: `PostDetailView.composer: CommentComposerState`, `submitComposer() async`, and the new `CommentView` signature — `CommentView(postID:comment:tone:isInteractive:editingCommentID:replyTargetID:draftCommentBody:onBeginEdit:onConfirmEdit:onReply:onDelete:onReport:onBlockAuthor:)` where `onReply: ((Comment) -> Void)?`. Task 5 modifies `CommentView` further and relies on its `tone` property existing.

- [ ] **Step 1: Swap PostDetailView state**

In `On Board/Views/Post/PostDetailView.swift`, replace lines 26-31:

```swift
    // Comment editing / replying
    @State var editingCommentID: UUID?
    @State var draftCommentBody = ""
    @State var replyingToCommentID: UUID?
    @State var newCommentDraft = ""
    @FocusState var isNewCommentFocused: Bool
```

with:

```swift
    // Comment editing / composing
    @State var editingCommentID: UUID?
    @State var draftCommentBody = ""
    @State var composer = CommentComposerState()
```

- [ ] **Step 2: Replace the bottom safeAreaInset and add scroll-to-reply**

In the same file, wrap the entire current `body` contents in a `ScrollViewReader`: immediately after `var body: some View {` insert `ScrollViewReader { proxy in`, add a matching closing brace before `body`'s final `}`, and re-indent. Then attach to the wrapped content (after the existing `.animation(.smooth(duration: 0.3), value: store.clearingBannerText != nil)` line):

```swift
            .onChange(of: composer.target) { _, target in
                guard let parentID = target?.replyParentID else { return }
                withAnimation(.smooth(duration: 0.35)) {
                    proxy.scrollTo(parentID, anchor: .center)
                }
            }
```

Replace the bottom inset (currently lines 149-159):

```swift
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !editMode {
                PostActionBar(
                    tone: tone,
                    counts: livePost.reactionCounts,
                    selectedReaction: selectedReaction,
                    isInteractive: !isReadOnly && !isCommentEditing && !editMode,
                    isRecord: isReadOnly
                )
            }
        }
```

with:

```swift
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Hidden while editing a post OR a comment — both put the keyboard
            // up for a different text session, and the bar previously rode the
            // keyboard into the content (the screenshot collision).
            if !editMode && !isCommentEditing {
                CommentComposerBar(
                    tone: tone,
                    counts: livePost.reactionCounts,
                    selectedReaction: selectedReaction,
                    composer: $composer,
                    isReadOnly: isReadOnly,
                    isRecord: isReadOnly,
                    onPost: submitComposer
                )
            }
        }
```

- [ ] **Step 3: Update the logic file**

In `On Board/Views/Post/PostDetailView+Logic.swift`, line 96, replace `replyingToCommentID = nil` with `withAnimation(.smooth(duration: 0.35)) { composer.dismiss() }` inside `beginCommentEditing` (editing and composing are mutually exclusive; the bar hides via `isCommentEditing`).

Replace `postNewComment` (lines 121-129) with:

```swift
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
```

- [ ] **Step 4: Remove the top composer and rewire CommentView call sites**

In `On Board/Views/Post/PostDetailView+Views.swift`, delete the `NewCommentComposer` block (lines 212-220):

```swift
        if !isReadOnly {
            NewCommentComposer(
                draft: $newCommentDraft,
                isFocused: $isNewCommentFocused,
                tone: tone,
                isDisabled: isCommentEditing,
                onPost: postNewComment
            )
        }
```

In the `ForEach` at ~line 234, update the `CommentView` call: add `tone: tone,` after `comment: reply/comment,`, rename the `replyingToCommentID: replyingToCommentID,` argument to `replyTargetID: composer.target?.replyParentID,`, replace the `onReply`/`onCancelReply` pair:

```swift
                        onReply: { commentID in
                            cancelCommentEditing()
                            replyingToCommentID = commentID
                        },
                        onCancelReply: { replyingToCommentID = nil },
```

with:

```swift
                        onReply: { comment in
                            cancelCommentEditing()
                            withAnimation(.smooth(duration: 0.35)) {
                                composer.beginReply(parentID: comment.id, handle: comment.author)
                            }
                        },
```

- [ ] **Step 5: Strip the inline reply composer out of CommentView**

In `On Board/Views/Post/CommentView.swift`:

1. Property changes — replace `var replyingToCommentID: UUID?` with `let tone: PostTone` (placed after `comment`) plus `var replyTargetID: UUID?`; change `var onReply: ((UUID) -> Void)?` to `var onReply: ((Comment) -> Void)?`; delete `var onCancelReply: (() -> Void)?`, `@FocusState private var isReplyFocused: Bool`, `@State private var replyDraft = ""`, `@State private var isPostingReply = false`.
2. Delete the whole `inlineReplyComposer` view (lines 96-139), the `postReply()` func (lines 141-151), and the body block that mounts it (lines 57-60):

```swift
            if replyingToCommentID == comment.id {
                inlineReplyComposer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
```

3. Also delete `.animation(.smooth(duration: 0.3), value: replyingToCommentID)` from the body (line 93) — the highlight animates via the `replyTargetID` change below.
4. Update the recursive `CommentView(...)` call inside the replies `ForEach` to the new signature (add `tone: tone,`, rename to `replyTargetID: replyTargetID,`, drop `onCancelReply:`).
5. Change the reply button action from `onReply?(comment.id)` to `onReply?(comment)`.
6. Reply-target highlight + scroll anchor — on `commentContent`'s outer `HStack` (the one starting `HStack(alignment: .top, spacing: 10)`), after `.opacity(isDimmed ? 0.32 : 1)` add:

```swift
        .background {
            if replyTargetID == comment.id {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tone.color.opacity(0.10))
                    .padding(-6)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: replyTargetID)
        .id(comment.id)
```

- [ ] **Step 6: Delete the orphaned files**

```bash
cd "/Users/jawadkhadra/On Board/onboard-ios"
grep -rn "NewCommentComposer\|PostActionBar" --include="*.swift" "On Board" "On BoardTests" "On BoardUITests" Styling
```

Expected: no hits outside the two files themselves. Then:

```bash
rm "On Board/Views/Post/NewCommentComposer.swift" "On Board/Views/Post/PostActionBar.swift"
```

- [ ] **Step 7: Build and run the full unit suite**

Run the build check (expected `** BUILD SUCCEEDED **`), then the full test run from Global Constraints. Expected: `✔ Test run with 94 tests in 34 suites passed` (84 pre-existing + 10 from Tasks 1-2); the count matters less than zero failures.

- [ ] **Step 8: Commit**

```bash
cd "/Users/jawadkhadra/On Board/onboard-ios"
git add "On Board/Views/Post/PostDetailView.swift" "On Board/Views/Post/PostDetailView+Logic.swift" "On Board/Views/Post/PostDetailView+Views.swift" "On Board/Views/Post/CommentView.swift" "On Board/Views/Post/NewCommentComposer.swift" "On Board/Views/Post/PostActionBar.swift"
git commit -m "Unify comment entry into the two-state bottom composer bar

Replaces the top NewCommentComposer box and CommentView's inline reply
mini-composer with CommentComposerBar; replies target the shared
composer via a context chip, the target comment is highlighted and
scrolled into view, and the bar hides during comment editing (fixing
the reaction-bar/keyboard collision)."
```

---

### Task 5: Collapsible threads with tone-tinted capsule lines

**Files:**
- Modify: `On Board/Views/Post/CommentView.swift`

**Interfaces:**
- Consumes: `CommentView.tone` (Task 4), `Comment.threadCount` (Task 2), `@AppStorage("hapticsEnabled")` convention.
- Produces: no new external surface — `CommentView`'s signature is unchanged from Task 4.

- [ ] **Step 1: Add collapse state and haptics gate**

In `CommentView.swift` add alongside the other `@State` properties:

```swift
    @State private var isCollapsed = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
```

- [ ] **Step 2: Replace the replies block**

Replace the `if !comment.replies.isEmpty { ... }` block (post-Task 4 it contains the `HStack` with the `Rectangle` line and the replies `ForEach`) with:

```swift
            if !comment.replies.isEmpty {
                Group {
                    if isCollapsed {
                        collapsedRepliesPill
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            threadLine

                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(comment.replies) { reply in
                                    CommentView(
                                        postID: postID,
                                        comment: reply,
                                        tone: tone,
                                        isInteractive: isInteractive,
                                        editingCommentID: editingCommentID,
                                        replyTargetID: replyTargetID,
                                        draftCommentBody: $draftCommentBody,
                                        onBeginEdit: onBeginEdit,
                                        onConfirmEdit: onConfirmEdit,
                                        onReply: onReply,
                                        onDelete: onDelete,
                                        onReport: onReport,
                                        onBlockAuthor: onBlockAuthor
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .sensoryFeedback(trigger: isCollapsed) { _, _ in
                    hapticsEnabled ? .impact(weight: .light) : nil
                }
            }
```

- [ ] **Step 3: Add the line and pill views**

Add to `CommentView`:

```swift
    /// The 2pt visible capsule sits centered in a 14pt strip whose hit area is
    /// inset a further -5pt on each side (≥24pt effective target) — the line
    /// itself is far too thin to tap.
    private var threadLine: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { isCollapsed = true }
        } label: {
            Capsule(style: .continuous)
                .fill(tone.color.opacity(isDimmed ? 0.12 : 0.30))
                .frame(width: 2)
                .frame(width: 14)
                .contentShape(Rectangle().inset(by: -5))
                .opacity(isDimmed ? 0.32 : 1)
        }
        .buttonStyle(.plain)
        .disabled(editingCommentID != nil)
        .accessibilityLabel("Collapse replies")
    }

    private var collapsedRepliesPill: some View {
        let hiddenCount = comment.threadCount - 1
        return Button {
            withAnimation(.smooth(duration: 0.3)) { isCollapsed = false }
        } label: {
            Label("Show \(hiddenCount) \(hiddenCount == 1 ? "reply" : "replies")", systemImage: "chevron.down")
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(tone.color.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand \(hiddenCount) hidden \(hiddenCount == 1 ? "reply" : "replies")")
        .padding(.leading, 14)
        .opacity(isDimmed ? 0.32 : 1)
    }
```

Note the indent math: the old layout was a 1.5pt line + 12pt HStack spacing (content starts at ~13.5pt); the new one is a 14pt strip + 0 spacing (content starts at 14pt) — visually equivalent. If it looks off on device, tune the strip's outer `.frame(width:)` only.

- [ ] **Step 4: Build and test**

Run the build check (expected `** BUILD SUCCEEDED **`) and the full unit suite (expected: all pass, same counts as Task 4).

- [ ] **Step 5: Commit**

```bash
cd "/Users/jawadkhadra/On Board/onboard-ios"
git add "On Board/Views/Post/CommentView.swift"
git commit -m "Make reply threads collapsible via tone-tinted tappable capsule lines"
```

---

### Task 6: Full verification pass

**Files:**
- None created — this task verifies and fixes.

- [ ] **Step 1: Full unit suite + build**

Run both commands from Global Constraints. Expected: `** BUILD SUCCEEDED **` and `✔ Test run … passed` with zero failures.

- [ ] **Step 2: Manual walkthrough in mock mode**

Launch the app in the simulator in mock mode (no `Secrets.xcconfig` → mocks; seed a session with `-mock.auth.session <hex>` per CLAUDE.md if sign-in is in the way; `On BoardUITests/PolishWalkthroughUITests.swift` has a ready-made hex blob and launch helper to copy from). Verify against the spec's checklist:

1. Post detail shows reaction pills + circle button; tapping the circle morphs it into the composer, keyboard rises, pills gone.
2. Composer ✕ button, keyboard swipe-down, and Done all return to browse; a typed draft survives dismissal and reappears on re-open.
3. Reply on a nested comment: chip shows the right handle, the target comment highlights and scrolls into view, chip ✕ reverts to "Add a comment…" without losing the draft.
4. Posting (send arrow) shows the spinner, disables double-submit, clears the draft, and lands the comment under the right parent.
5. Editing a comment hides the bottom bar entirely; Save/cancel brings it back.
6. Tapping a thread line collapses to "Show N replies" with the correct recursive count and a light haptic; tapping expands.
7. Archived post (record layout): no circle button, record pill strip intact.
8. Accessibility spot-checks: largest Dynamic Type (reactions collapse to Menu, circle button still present), Reduce Motion (crossfade, no shape morph), VoiceOver reads "Collapse replies"/"Expand N hidden replies"/"Add a comment"/"Close composer".

If no interactive simulator is available, follow the headless walkthrough pattern (drive via a temporary UI test + `simctl io recordVideo`, decode frames with AVAssetReader — see the PolishWalkthroughUITests header and memory notes).

- [ ] **Step 3: Fix anything found, re-run Step 1, commit fixes**

```bash
cd "/Users/jawadkhadra/On Board/onboard-ios"
git add <only-the-files-you-fixed>
git commit -m "Polish comment composer verification findings"
```
