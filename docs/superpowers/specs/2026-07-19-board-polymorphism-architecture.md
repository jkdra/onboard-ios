# Board Polymorphism Architecture

*Future-proofing for multi-campus and, eventually, location-based (non-college) boards.*

## Context

On Board today is college-centric: you join a board by verifying a `.edu` email. We
want to open up to (1) more campuses and (2) eventually **location-based local boards**
for non-students. The goal of this doc is **not** to build those now — it's to set the
schema and backend up so adding them later is cheap and additive, while we're still
pre-launch with near-zero data (the cheapest possible time to reshape).

Verified against production 2026-07-19 (tags=1, posts=6, boards=1 — reshaping now is
effectively free).

## Current state

**Already generic — keep as-is (no college assumption to remove):**
- Content spine: `boards → board_weeks → posts → comments/reactions/tags`, everything
  keyed on `board_id`. A location board's content flows through the identical tables.
- Access/read layer: `board_members` (M:N, with `role`) is the universal membership join.
  `list_accessible_boards`, `get_active_board_week`, and digest targeting all read it and
  **never branch on how a user joined**. Multi-board membership is already possible at the
  data layer.

**College-locked — isolated to exactly two seams:**
1. **Eligibility** (how you earn a `board_members` row): `school_domains` (`.edu → board`,
   with a `\.edu$` CHECK) + `lookup_school_for_email` / `begin_school_email_verification` /
   `complete_school_email_verification_v2`, which set `profiles.board_id` and insert
   `board_members`.
2. **Onboarding + identity**: the `onboarding_step` enum has `school_verify` / `waitlist`;
   `profiles.verified_school_email` / `pending_school_email` are the college identity anchor.

## Design principles

1. **`kind` is a descriptor, not a control switch.** `boards.kind` labels a board and
   selects onboarding copy/step — it must never become `if kind='college' … elif …` inside
   membership logic.
2. **Eligibility = pluggable sources → `board_members`.** Each mechanism (email-domain,
   geo-region, invite, open) is an independent table + resolver that *unions* into
   `board_members`. Adding a mechanism touches nothing existing (open/closed). A single
   board may declare multiple sources (e.g. a campus board that also accepts a radius).
   Deliberately **not** a generic rules engine — concrete source tables, no policy DSL.
3. **`board_members` is membership truth; `profiles.board_id` is the active-board pointer**
   (UI state — "which board am I currently viewing"). This contract is what makes a user
   belonging to their campus *and* their neighborhood board coherent later.

## Target model

- `boards`: add `kind` enum (`college` | `location` | …), `status` enum
  (`active` | `waitlist` | `coming_soon`), and nullable geo (`center_lat`, `center_lng`,
  `radius_m`) used only by location boards.
- Eligibility sources (each optional per board):
  - `school_domains` (exists) — email-domain match. *This is "the email-domain source,"
    not "the only way in."*
  - `board_regions` (future) — geo/city match for location boards.
  - `board_invites` (future, if ever needed) — code/referral.
- Resolver `eligible_boards(user attrs)` unions all sources → candidate boards →
  `board_members` grant. Today it's just the `school_domains` branch.
- Onboarding: one `verify` step whose UI is chosen by the target board's eligibility
  source(s); the enum grows by ~one value (`location_verify`) when location ships.
- `tags`: `tags.board_id` (board-scoped), consistent with the spine.

## Now (Tier 1) — seams only, no new board types

- **Tags board-scoping** (`tags.board_id`, board-scoped `search_tags`) + `post_count`
  drift fix (currently unmaintained — reads 3 vs 2 real links).
- **`boards.kind` + `boards.status`** (+ optional nullable geo columns). Default the
  existing board to `college` / `active`.
- Document the eligibility-source contract; keep `school_domains` as the email-domain
  source. **No new eligibility tables yet** — the sources pattern is what lets us add them
  later touching nothing else, so there's no cost to deferring.

## Cross-board trending (the one intended exception to board-scoping)

Tags are board-scoped by default, but a topic popular across *many* boards (e.g.
`finals`, `housing`) may be worth surfacing on a board that hasn't used it yet. Design (b)
makes this a cheap **read-time overlay**, not a storage change: because per-board rows
share the `name`, `name` is a stable cross-board key, so "trending everywhere" is an
aggregation:

```sql
select name, count(distinct board_id) as board_spread, sum(post_count) as total_uses
from public.tags group by name;
```

Metric design:
- **Primary signal is breadth, not volume:** `count(distinct board_id)` (spread), so a tag
  huge on one board doesn't qualify while a tag on many boards does.
- **Relative threshold** (`spread ≥ max(3, ceil(0.10 × active_boards))`) so it scales as
  boards grow instead of everything qualifying.
- **Recency** via `last_used_at` (already maintained) — spread over ~30 days, not all time.
- **Inflation guard:** only count a board toward spread if the tag has real adoption there
  (e.g. ≥2 posts).
- **Governance:** gate the global tier with an editorial allow/deny list — pure popularity
  can promote something offensive; also handy for seeding canonical tags at launch.

Surfacing: the picker unions board-local `search_tags(prefix, board_id)` with a
`trending_tags(prefix)` source, dedupes (a local tag that's also trending shows once, as
local), and labels the global-only rows. Picking a global suggestion seeds it locally via
`set_post_tags` (`on conflict (board_id, name)`) — no special-casing. Compute live now;
promote to a pg_cron-refreshed materialized view only if it ever gets heavy. **Deferred —
needs multi-board data + the picker UX; Tier 1 already keeps the `last_used_at` +
per-board `post_count` this relies on.**

## Later

- **Tier 2 (when location is a real product):** add `board_regions` + a resolver UNION
  branch + onboarding `location_verify`; scope the `.edu` CHECK to the college source only.
- **Tier 3 (app):** board switcher; `BoardStore` keyed by board (today it assumes a single
  `currentBoard`). Backend already supports the data.
- **Cross-board trending overlay** (above) — a `trending_tags` source + picker union.

## Proof the design works

Adding location boards later touches **only**: (1) a new `board_regions` table, (2) one
UNION branch in the resolver, (3) an onboarding `location_verify` UI, (4) the app board
switcher. Existing college code, the content spine, and the read layer are all untouched.

## Open questions (defer to the location product)

- Geo model: radius vs. city/admin region vs. zip?
- Location identity: device-location grant vs. user-chosen city?
- Is a user's "home" board a distinct concept, or purely their membership set + active pointer?
