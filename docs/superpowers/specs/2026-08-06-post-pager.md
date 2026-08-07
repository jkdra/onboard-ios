# The board reader — vertical post paging

**Status:** spec drafted 2026-08-06; research spike pending on the zoom
retarget. Not started.
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

## Open questions for the spike

1. Does zoom `sourceID` re-resolve at pop time from updated destination
   state? (Prototype on a scratch project, both button-pop and interactive
   edge-swipe — the interactive path re-resolves geometry per frame and is
   where the documented collapse artifact lives.)
2. Pager construction: `.scrollTargetBehavior(.paging)` vs rotated TabView
   vs UIPageViewController bridge — which gives TikTok-feel with reliable
   current-page callbacks on iOS 18?
3. Gesture handoff implementation for expand/collapse (SwiftUI-native vs
   UIGestureRecognizerRepresentable).
