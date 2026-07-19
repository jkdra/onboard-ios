# Board Future Work — deferred backlog

Actionable follow-ups deferred from the 2026-07-19 Tier-1 pass. Design rationale
lives in `docs/superpowers/specs/2026-07-19-board-polymorphism-architecture.md`;
this file is just the checklist. **Tier 1 (board-scoped tags, count fix,
`boards.kind`/`status` seams) is already applied.**

## Tier 2 — eligibility generalization + location boards
*Trigger: when location-based (non-college) boards become a real product.*

- [ ] `board_regions` table (board_id + geo/city) as a second eligibility **source**
      alongside `school_domains`. Do NOT branch on `boards.kind` — add a source.
- [ ] Eligibility resolver that **unions** all sources for a user → `board_members`
      grant (today it's just the `school_domains` branch).
- [ ] Onboarding: add a `location_verify` step; pick the verify UI by the target
      board's eligibility source(s) rather than hardcoding `school_verify`.
- [ ] Scope the `\.edu$` CHECK to the college source only (or drop it there) so it
      never blocks non-college domains.
- [ ] iOS: add `kind`/`status` to the `Board` model (optional, `decodeIfPresent`)
      **and** source `currentBoard` from a real board fetch instead of the
      `Board(id:name:)` stub, so `kind`/`status` are consistent everywhere. Update
      `list_accessible_boards` to return them.

## Tier 3 — multi-board app support
*Trigger: when a user can belong to more than one board (campus + neighborhood).*

- [ ] Treat `board_members` as membership truth, `profiles.board_id` as the
      active-board pointer (UI state). Audit any code assuming a single board.
- [ ] `BoardStore` keyed by board instead of a single `currentBoard`.
- [ ] Board switcher UI.

## Tappable tag feed
*Trigger: when tag-browsing discovery is worth a view + RPC. Tags are decorative today.*

- [ ] Tap a tag → per-board feed of posts with that tag (all weeks incl. archive),
      interactive-glass chips. Full blueprint:
      `docs/superpowers/specs/2026-07-19-tappable-tag-feed.md`.

## Cross-board trending (the one exception to board-scoping)
*Trigger: once there are enough boards that a shared topic is worth surfacing.*

- [ ] `trending_tags(prefix)` source: aggregate `tags group by name`, ranked by
      **board spread** = `count(distinct board_id)` (breadth, not raw volume),
      windowed by `last_used_at` (~30d), relative threshold
      `spread >= max(3, ceil(0.10 * active_boards))`, inflation guard (>=2 posts/board).
- [ ] Picker unions board-local `search_tags` with `trending_tags`, dedupes, labels
      the global-only rows ("Popular across On Board"). Picking one seeds it locally
      via `set_post_tags` (`on conflict (board_id, name)`).
- [ ] Editorial allow/deny list on the global tier (abuse/quality; also seeds
      canonical tags at launch).
- [ ] Promote to a pg_cron-refreshed materialized view only if live aggregation
      ever gets heavy.
