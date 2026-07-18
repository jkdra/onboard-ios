# Comment composer & thread interaction redesign — design

**Date:** 2026-07-18 · **Status:** approved design, pending implementation plan

## Problem

Screenshots from a live device session surfaced three issues in `PostDetailView`'s
comment experience:

1. **Keyboard collision.** The reaction bar (`PostActionBar`, pinned via
   `safeAreaInset(edge: .bottom)` at `PostDetailView.swift:149`) rides the keyboard
   up and floats directly over the comment thread while the user is composing a
   reply — reaction pills overlapping comment text, the keyboard "Done" pill
   overlapping the reaction pills.
2. **Material mismatch.** Both composers (`NewCommentComposer` and `CommentView`'s
   `inlineReplyComposer`) are flat gray slabs (`.secondary.opacity(0.08)` rounded
   rects) on the tone-tinted background, while everything else on the screen is
   toned/glassy. The top composer also parks ~90pt of empty gray box between the
   "Comments" header and the first comment.
3. **Three text-entry mechanisms.** New comment (top box), reply (inline
   mini-composer with per-comment `replyDraft` state, squeezed by thread
   indentation), and edit (in-place morph with toolbar Save) — each with its own
   draft, focus state, and submit path, with mutual exclusion hand-wired through
   callbacks.

Additionally, long reply chains cannot be collapsed, and the thread line is a
hard-edged 1.5pt `Rectangle` with no interactivity.

## Alternatives considered and rejected

- **Comment bubbles** (Miiverse-style balloons): deferred. Floating text keeps
  the forum feel; revisit only as the characterful balloon, never a generic card.
- **System bottom toolbar** (`.bottomBar`): rejected. Glass-on-glass rules would
  force the reaction pills to solid fills (recreating the flat-slab problem), and
  the managed toolbar can't host the `GlassEffectContainer` morph that is the
  centerpiece of this design. The toolbar's scroll-edge/keyboard behaviors are
  replicable in the custom bar.
- **Swipe-gated composer**: rejected. Hides the app's primary engagement action
  behind an undiscoverable gesture and competes with three existing gesture
  owners (edge-swipe back — load-bearing for zoom transitions — scroll, and
  interactive keyboard dismiss).
- **Separate spatial regions for reactions vs. commenting** (the current design):
  replaced. The separation is semantic, not spatial, and the current layout
  collapses exactly when the keyboard appears. Time-multiplexing one bottom slot
  keeps the semantics separated more strictly (the two never coexist on screen).

## Design

### 1. Bottom bar: two-state morph

The bottom `safeAreaInset` slot becomes a single component with two mutually
exclusive states:

- **Browse state** — the existing `ReactionBar` pill cluster, plus a new
  **circular Comment button** trailing it (SF Symbol `bubble` family icon,
  glass circle, same height as the pills). The circle-vs-capsules silhouette
  distinction expresses the reaction/comment semantic split. `ReactionBar`'s
  existing record layout (archived weeks) and accessibility-size `Menu` layout
  are preserved; the Comment button appears alongside both except when
  `isReadOnly` (archived posts get no composer entry point, matching today's
  behavior of hiding `NewCommentComposer`).
- **Compose state** — a glass composer: multiline `TextField` ("Add a comment…"),
  tone-colored send button (spinner while posting, disabled when
  trimmed-empty — port `NewCommentComposer`'s `isPosting` double-submit guard),
  and, when replying, a context chip above the field: "↩ Replying to @handle ✕".
  Tapping the chip's ✕ clears the reply target (compose state continues,
  targeting a new top-level comment). Exiting compose is always one obvious
  tap: a dedicated ✕ close button on the composer itself (mirroring the old
  inline reply composer's cancel), and dismissing the keyboard (swipe or Done)
  exits equally. The reaction pills are **absent** in this state — the keyboard
  collision becomes impossible by construction.

**The morph:** on iOS 26, the bar lives in a `GlassEffectContainer`; the circular
Comment button and the composer field share a `glassEffectID`, so tapping the
circle makes it bloom into the text field while the pills scale/slide away, and
the reverse on dismiss. Pre-26 fallback: `matchedGeometryEffect` between circle
and field with the pills fading — same choreography, plain materials (the
existing `systemBackground.opacity(0.45)` fill language). With Reduce Motion, a
plain crossfade.

### 2. Entry points and reply targeting

- Tapping the **circle button** → compose state targeting a new top-level comment.
- Tapping **Reply on any comment** → compose state targeting that comment
  (context chip shows its author handle). `CommentView`'s `inlineReplyComposer`
  and per-comment `replyDraft` state are **deleted**; the reply button's only job
  is setting the shared composer target.
- The **top `NewCommentComposer` box is removed** entirely. The "Comments N"
  header and empty-state line stay.
- While a reply target is active, the target comment gets a subtle tone-tinted
  highlight so the connection is visible beyond the chip, and the scroll view
  scrolls the target comment into view above the keyboard (`ScrollViewReader`).
- One shared draft (`composerDraft`) plus a target enum:
  `enum ComposerTarget { case newComment; case reply(parentID: UUID, handle: String) }`.
  Switching targets keeps the draft text (it's still about the same post).
  Exiting to browse state always retains a non-empty draft for the session, so
  an accidental keyboard dismiss never loses writing.

### 3. Editing: unchanged mechanism, fixed collision

In-place editing (text morphs to a `TextField`, toolbar Save) stays — it matches
the app-wide edit-morph language. One change: while `editingCommentID != nil`,
the bottom bar **hides entirely** (today it stays pinned, dimmed, and rides the
keyboard — the same collision as replies). It already hides during post
`editMode`; comment editing joins that condition.

### 4. Collapsible threads + tone-tinted thread lines

- The thread line (`CommentView.swift:64`) becomes a `Capsule` tinted with the
  post's tone at low opacity (`tone.color.opacity(~0.25)`), keeping the dimmed
  variant for edit mode. `PostTone` is threaded into `CommentView` as a new
  parameter from `PostDetailView`.
- The line becomes tappable: an invisible widened `contentShape` strip (≥24pt)
  toggles `@State private var isCollapsed` on that `CommentView`. Collapsed, the
  subtree is replaced by a "Show N replies" pill where
  `N = comment.threadCount - 1` (the existing recursive counter at
  `PostDetailView+Views.swift:419` — direct-children counts would undercount).
  Tapping the pill (or the line) expands. Collapse state is per-view `@State`;
  `ForEach` keys by comment ID, so it survives the post-submit thread reload.
- A light impact haptic on collapse/expand via `.sensoryFeedback`, gated on the
  existing `hapticsEnabled` AppStorage flag (matching `CommentVoteBar` /
  `ReactionBar`; never raw `UIImpactFeedbackGenerator`).
- Accessibility: the line/pill exposes a proper button with
  "Collapse replies" / "Expand N replies" labels — a 1.5pt line is not a
  discoverable VoiceOver target.

### 5. What does NOT change

- Vote bar, double-tap-to-like, comment menus (edit/delete/report/block).
- `BoardStore` comment logic — this is a view-layer redesign; optimistic
  create/edit/delete/vote paths, `threadCount`, and caching are untouched.
- Haptics on votes/reactions (already shipped).
- The clearing banner (top `safeAreaInset`), post edit mode, read-only rules.

## State model summary

`PostDetailView` gains `composerTarget: ComposerTarget?` (nil = browse state) and
`composerDraft: String`, replacing `newCommentDraft`/`isNewCommentFocused` and
every `CommentView`'s `replyDraft`/`isPostingReply`/`replyingToCommentID`
plumbing. `editingCommentID`/`draftCommentBody` (edit path) remain. Invariant:
`composerTarget` and `editingCommentID` are never both non-nil (starting either
clears the other, as `onReply`/`beginCommentEditing` already do today).

## Testing

- Unit: `ComposerTarget` transitions (reply→new keeps draft, edit cancels
  compose, read-only exposes no target); collapsed-count math on a nested
  fixture (threadCount - 1).
- Existing comment store tests must stay green (no store changes expected).
- Visual/manual in mock mode: morph in both states and both OS eras (iOS 26 sim
  + iOS 18 destination), keyboard up with reply targeted at a deeply nested
  comment (the screenshot scenario), archived-week record layout, accessibility
  text sizes (Menu layout + circle button), Reduce Motion, VoiceOver pass over
  the thread line.

## Out of scope / follow-ups

- Miiverse-style comment balloons (revisit post-launch if the itch persists).
- Persisting collapse state across navigation.
- Any change to comment pagination or realtime (deliberately absent per
  architecture docs).
