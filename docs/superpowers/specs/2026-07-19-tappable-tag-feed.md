# Tappable Tag Feed (deferred)

*Implementation blueprint for making tags tappable → a per-board tag feed spanning
all weeks (incl. archive), with interactive-glass chips. Deferred by choice on
2026-07-19; tags stay decorative for now. This is the "Tappable Full" option from
that discussion. Backlog pointer lives in `2026-07-19-board-future-work.md`.*

## Goal

Tapping a tag (e.g. `#housing`) opens a feed of **this board's** posts carrying that
tag, across the current week and archived weeks. Once tags are interactive, give the
chips interactive glass (consistent with the app's "glass = touchable" grammar — the
reason they're flat today is that a static glass chip is a false affordance).

## Current state (2026-07-19)

- Tags render as flat `Color.primary.opacity(0.1)` capsules in **four** places, all
  non-interactive:
  - `On Board/Views/Feed/GridCard.swift` → `tagChip(_:)` (feed cards)
  - `On Board/Views/Post/PostDetailView+Views.swift` → detail (~line 154) and the
    record layout (~line 356)
  - `On Board/Views/Feed/NewPostView.swift` → composer chips (~line 197)
- Tags are board-scoped (`tags.board_id`, `unique(board_id, name)`); `post_count` is
  correct (single trigger pair). `search_tags(prefix, p_board_id, p_limit)` exists.
- No `Tag` model change is needed for this feature — posts already carry `tags`.

## Backend

Add an RPC modeled on `fetch_posts_for_week` (in `supabase/migrations/` /
`SupabaseBoardService+Posts.swift`), so it inherits the same moderation/`hidden_at`
and block filters — do NOT hand-roll new filtering:

```sql
create or replace function public.fetch_posts_by_tag(p_board_id uuid, p_tag text, p_limit integer default 100)
returns setof <same shape as fetch_posts_for_week>
language sql security definer set search_path to 'public' as $$
  -- posts on p_board_id (via board_weeks) whose post_tags include the tag row
  -- (board_id, lower(p_tag)); reuse fetch_posts_for_week's select list + joins +
  -- hidden_at / block filtering; order by created_at desc; limit p_limit.
$$;
-- grant execute to authenticated, service_role;  -- (NOT anon; match search_tags)
```

Normalize `p_tag` the same way `set_post_tags` does (`lower` + strip non-alphanumerics)
before matching. Add the client method to `BoardService` + `SupabaseBoardService`:
`fetchPosts(byTag:boardID:) async throws -> [Post]`, decoding `RemotePostRow`.

## Navigation & view

- Add `case tag(name: String)` to `BoardRoute` (`On Board/Models/Board.swift`).
  Board is implicit (current board).
- Handle it in **ContentView's single** `navigationDestination(for: BoardRoute.self)`
  — production has exactly one (see CLAUDE.md "Zoom navigation transitions"). Do NOT
  add a second destination elsewhere.
- New `TagFeedView(tag:)`: fetches via the store, renders matching posts with the
  existing `BoardFeedView` masonry (reuse `GridCard`).
- **Zoom-transition rule (CLAUDE.md #2):** a post opened *from* a tag feed shows ids
  that may also be alive in the main feed / profile. Add a distinct source route
  (e.g. `.postFromTag(postID:tag:)`) so the zoom source stays unique, exactly as
  `.post` vs `.postFromProfile` do today. Thread the shared `cardNamespace`; never a
  local `@Namespace`.

## Store

- `BoardStore` method to fetch + merge tag-feed posts. Reuse `mergeWeekPosts(_:reactions:)`
  — tag-feed posts can belong to weeks not currently loaded, and `mergeWeekPosts`
  already appends + indexes + builds proxies without a full rebuild. Cache per tag if
  revisits are common (optional; a tag feed is a drill-down, so a fresh fetch each open
  is acceptable v1).

## Interactive chips

- Extract a shared `TagChip` view (the four sites duplicate the chip today — worth
  consolidating when they become interactive). Wrap in `NavigationLink(value:
  BoardRoute.tag(name:))`, and switch the background to
  `GlassBackground(shape: Capsule(style: .continuous), interactive: true)` (the shared
  primitive in `Styling/Styles/GlassBackground.swift`).
- Composer chips (`NewPostView`) stay non-navigating (they edit selection), so the
  shared chip needs an "interactive vs. plain" mode — don't make the composer chips
  push a feed.

## Edge cases

- Archived-week posts appear read-only in the tag feed (respect `isReadOnly`).
- Blocked authors' posts already excluded server-side (inherited from
  `fetch_posts_for_week` filters).
- Empty state: a tag with no visible posts (all hidden/blocked) → a simple "No posts
  with #tag" placeholder.

## Verification

- `xcodebuild build` + full test suite.
- Manual: tap a tag in feed and in post detail → tag feed loads matching posts →
  tap a post → detail via zoom (verify the interactive edge-swipe pop doesn't collapse
  — the distinct `.postFromTag` source is what prevents it). Confirm archived posts are
  read-only and the composer chips still just edit selection.
- Advisor pass after the migration; confirm `fetch_posts_by_tag` is not anon-executable.

## Scope estimate

One migration + one RPC, one `BoardService` method + impl, one `BoardRoute` case + a
`TagFeedView`, a shared `TagChip`, and a `BoardStore` fetch/merge method. Medium — a
real feature, not a finishing touch (which is why it was deferred).
