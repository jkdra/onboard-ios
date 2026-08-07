# The board reader — vertical post paging

**Status:** spec drafted 2026-08-06; research pass complete same day —
construction and gesture approach DECIDED below; one empirical spike remains
(zoom retarget verification on-device). Not started.
**Depends on:** rich-text renderer (`feature/rich-text-posts`), comments
infra, zoom navigation transition.

## Why

The current browse loop — open post, back, hunt the grid for the next card,
tap — makes reading the whole board feel like work. The board is FINITE by
design (a few dozen posts, cleared Monday), which is the one thing infinite
feeds can't offer: an ending. Paging turns catch-up into a finishable ritual:
flip through, react along the way, land on "you're caught up."

The masonry grid remains the HOME. It is the app's identity (the bulletin
board) and does a job paging can't: spatial overview, tone at a glance. Grid
= browse; pager = read. The pager is entered exactly the way post detail is
entered today.

## The screen

Each page is one post, condensed to be glanceable:

- Author row, then content. Long text truncates (the renderer's single-Text
  global line limit already supports this) with an expand affordance;
  gradient fade + "more". Expanding hands over to an internal scroll (see
  Gestures). Collapsing hands back.
- Image posts: image anchored at the BOTTOM of the page regardless of text
  length — text gets the top, image gets the bottom, both always visible.
- Reaction bar stays pinned at the page bottom (it already exists per post).
- Comments are NOT inline. A comment affordance opens a half-sheet (not a
  push — a push leaves the paging context; the sheet keeps the post behind
  it and drops back into flow). Sheet header = the condensed post: truncated
  opening, small, so the comment thread never loses its subject. Existing
  CommentComposerSheet/bar infra carries over.
- Archived posts page the same, read-only (no reaction bar), as detail does
  today.

## Gestures

- **Swipe UP = next post, DOWN = previous.** TikTok/Reels muscle memory; the
  user's demographic has it burned in. (The original sketch said down-for-
  next; inverted deliberately — down also collides with sheet-dismiss and
  the zoom pop's grammar.)
- The page gesture exists ONLY in the collapsed state. Expanded text scrolls
  internally; the pager reclaims the gesture when the inner scroll returns
  to rest/top. One owner at a time, no simultaneous arbitration.
- Horizontal edge-swipe pop and the back button behave per Navigation below.
- VoiceOver: the page gesture is invisible to assistive tech (CLAUDE.md
  rule) — expose explicit "Next post" / "Previous post" accessibility
  actions, and the completion state must be announced.

## Navigation — the back-transition invariant

**Popping the pager zooms into the card of the post the user is CURRENTLY
on, in whatever feed hosted it, with that card scrolled into the viewport.**
Paging from A to F and popping must land on F's card — matched source id,
correct route kind (`.post` vs `.postFromProfile`), grid scrolled so the
card exists on screen. Anything less snaps the user back to A's scroll
position with F in their head: disorientation, exactly what the feature
exists to remove.

Mechanics (pending the research spike):

- The zoom `sourceID` on the pushed destination must retarget as the current
  page changes — feasibility of live retargeting is the spike's question #1.
  Fallback ladder if it can't: replace-last-path-element without animation;
  failing that, crossfade pop after paging (never ship the collapse-to-zero
  artifact documented in CLAUDE.md's zoom rules).
- The host feed tracks the pager's current post (binding/preference) and
  scrolls the masonry to that card AS PAGING HAPPENS (cheap while covered),
  not at pop time — the source must already be laid out when pop resolves
  geometry, or LazyVStack recycling hands the transition a missing source.
- All four zoom-transition landmines in CLAUDE.md apply: one namespace,
  route-typed source ids, no ancestor transforms, source frame contains all
  drawing.
- Pager scope = the feed it was entered from: main feed pages this week's
  posts (skipping non-post feed items), a profile's grid pages that
  profile's posts, archive pages that week. Deep links (push notification →
  post) enter the pager in main-feed scope.

## Order, seen state, completion

- Page order = the feed's linear post order (masonry is a display transform;
  the store's order is canonical).
- **Start at the first unseen post** when entered from the countdown/"catch
  up" affordance; start at the tapped post when entered from a card. Seen =
  paged onto (dwell, not scroll-past-in-grid). Per-post seen set, client-
  side, persisted in CacheEnvelope (new Optional field per the cache rules;
  cleared with the week naturally since post ids die at reset). The server's
  unseen-count (push logic) stays what it is — coarse, last_seen_at-based;
  no new server state.
- **Completion:** paging past the last post lands on a terminal page — the
  Host (HostHappy), "You're caught up.", clears-in countdown, and a compose
  nudge ("add something to the board"). This is the weekly ritual's reward
  moment; keep it warm and small, not gamified.
- Posts arriving mid-session (poll/refresh) append naturally; deleted/
  blocked posts drop out of the page set the way sanitizeNavigationPath
  handles routes today.

## Performance

- Adjacent pages pre-render (lazy container with small lookahead); adjacent
  images pre-warm via the existing Nuke pipeline pattern (the ImageViewer
  warming precedent in PostDetailView).
- Comment threads load on sheet-open only (they already revalidate per
  post-open; don't prefetch threads for pages never dived into).

## Build stages

1. **Condensed detail + comments half-sheet** — no paging yet; the detail
   screen becomes the page layout. Ships alone as a cleaner post view.
2. **The pager** — vertical paging + back-transition invariant + scroll
   sync. The research spike gates the transition mechanics.
3. **Seen state + completion moment** — the ritual payoff.

Stage 1 is worth shipping even if 2 slips; nothing in it is throwaway.

## Decisions from the research pass (2026-08-06)

**Construction (decided):** `ScrollView(.vertical)` + `LazyVStack(spacing: 0)
.scrollTargetLayout()` + `.scrollTargetBehavior(.paging)`; every page
`.containerRelativeFrame([.horizontal, .vertical])` (paging is by container
extent — variable page heights drift); pager `ignoresSafeArea` with insets
INSIDE pages (iOS 26 paging-offset bug, forum 801904). Current page via the
`scrollPosition(id:)` BINDING — not `ScrollViewReader` (broken under Xcode
16/iOS 18, forum 765771) and not the `ScrollPosition` object (silent no-op
on iOS 26 beta, forum 793716). Settled-vs-dragging via `onScrollPhaseChange`;
per-page side effects (seen-marking) via `onScrollVisibilityChange`.
Rotated `TabView` is DISQUALIFIED — a rotated ancestor is exactly the
"nothing may transform the source from above" zoom killer in CLAUDE.md.
`UIPageViewController` bridge rejected: UIKit container between SwiftUI and
the zoom transition, plus a duplicated-page bug (forum 740470).

**Zoom retarget (fallback ladder, step 1 pending the spike):**
1. Destination's `.navigationTransition(.zoom(sourceID:in:))` driven by the
   pager's current route. UNDOCUMENTED whether SwiftUI re-reads it at pop —
   but the underlying UIKit machinery re-resolves the source at dismissal by
   design (WWDC24 10145; Douglas Hill's zoom guide: sourceViewProvider is
   re-invoked at dismiss precisely for cell reuse), and SwiftUI's interactive
   pop re-resolves source geometry per frame. Plausible; verify empirically
   on an iOS 18 DEVICE, both back-button and interactive swipe.
2. Load-bearing regardless: mirror the pager's current post into the grid's
   `scrollPosition(id:)` AS PAGING HAPPENS so the target card is realized
   and registered before pop. This converts the recycled-cell case into the
   normal case (Photos does the same scroll-into-place).
3. Residual no-source behavior is a CENTER-OF-CONTAINER zoom, not a
   collapse (the collapse-to-zero artifact is the wrong-namespace case, a
   different bug). Acceptable-ugly last resort.
4. If step 1 fails verification: conditional transition — keep `.zoom` when
   current == entry post, else `.navigationTransition(.automatic)`; if even
   that misbehaves, nil the namespace after first page-away (the existing
   nilable-namespace flag shape).
   Known OS bugs cluster on INTERACTIVE swipe-back (FB21078443 / forum
   807715: source item disappears, no workaround as of 26.2; forums 810944,
   807208) — QA that path on physical devices; the back button always looks
   fine and masks breakage.

**Gesture handoff (decided):** deterministic mode-switching, not live nested
scrolling. Collapsed page: inner content `.scrollDisabled(true)`, pager owns
the gesture. Expanded: flip — pager disabled, inner scroll owns it; hand
back when `onScrollGeometryChange` reports inner offset ≤ 0 and the drag
continues downward. Nested same-axis scroll views are arbitration roulette
(worse on iOS 26, forum 794212). If the two-mode feel disappoints, graduate
to `UIGestureRecognizerRepresentable` (iOS 18+) modeled on FluidGroup's
scrollview-interoperable-drag-gesture — no introspection.

**Seen state (decided):** `seenPostIDs: Set<UUID>` on BoardStore, marked when
a page becomes the SETTLED current page; persisted as a new Optional
CacheEnvelope field — added to the hand-written CodingKeys/init/encode, per
the envelope's Codable rule — keyed by week and dropped at reset. No server
round-trip (no cross-device requirement; the weekly reset bounds the set).

**Completion (note from the literature):** Instagram's "caught up" divider is
widely read as symbolic because suggested content restarts the scroll (CHI
2025). Ours can be sincere BECAUSE the board is finite — the terminal card
must be an actual end-state (Host moment, countdown, compose nudge), never a
segue into more content.

## Remaining spike

One scratch-project test: grid + paged detail, flip `sourceID` from state
after paging, pop via back button AND interactive swipe on an iOS 18 physical
device. Outcome selects rung 1 or rung 4 of the ladder. Everything else in
this spec is buildable without it (stages 1 and 3 don't touch the
transition).
