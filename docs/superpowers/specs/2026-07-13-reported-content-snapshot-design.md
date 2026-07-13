# Reported Content Snapshot — Design

## Context

This repo already has (as of 2026-07-13):
- `boards` → `board_weeks` → `posts` FK cascade on delete.
- `reports.post_id` → `posts.id` is `ON DELETE CASCADE`.
- A `BEFORE DELETE` trigger on `posts` (`handle_post_deletion_archive`) that, when a post has any report with status `pending` or `reviewed`, writes a snapshot of the post + its reports into `archived_reported_posts`, then clears its `reports` rows so the delete always proceeds.

Gap: that trigger only fires at delete time, and snapshots whatever the post's content looks like *then*. Posts are editable after publish (`BoardStore.updatePost` / `SupabaseBoardService.updatePost`), so a reported post that gets edited before it's ever deleted has its *original, reported* content silently lost — the archive would only ever show the edited (possibly innocuous) version.

## Goal

Preserve the post's content as it existed at the moment it was reported, independent of any later edit or deletion, for posts only (comments/profiles are explicitly out of scope for this pass).

## Design

### 1. Schema

```sql
alter table public.reports add column reported_content_snapshot jsonb;
```

Nullable — reports filed before this migration have no snapshot and never will (the original content at their report time is already unrecoverable).

### 2. `report_content()` RPC

For `p_target_type = 'post'`, capture the post's current `title`, `description`, `tone`, `image_url`, `image_aspect_ratio`, `author_id`, `author_handle`, `created_at` into a jsonb object and store it on the same row as `reported_content_snapshot`, in the same `insert ... values (...)` that creates the report. Comment/profile reports leave the column `null`.

The existing `on conflict do nothing` (one report per reporter per post) already prevents duplicate rows; a no-op insert stores no snapshot, which is correct.

### 3. `handle_post_deletion_archive()` trigger

The `v_reports` jsonb aggregation gains one more field per report: `r.reported_content_snapshot`. The final `archived_reported_posts.reports` array then carries, per report, the content *as it was when that specific report was filed* — which may legitimately differ report-to-report if the post was edited between them. The top-level `archived_reported_posts` columns (from `OLD.*`) remain the state *at deletion*, unchanged from the existing design. Both views are useful: one shows what was reported, the other shows what actually got deleted.

### 4. Edge cases

- Pre-migration reports with a `null` snapshot: `jsonb_build_object` carries the null through without erroring.
- A post reported twice at different times, edited in between: two distinct `reported_content_snapshot` values in the archived array — this is the intended signal, not a bug.
- No change to which report statuses count as unresolved (`pending`/`reviewed`), no change to the board→week→post cascade, no change to `reports.post_id`'s `ON DELETE CASCADE`.

## Non-goals

- Comments and profile reports are not snapshotted in this pass.
- No retention/cleanup policy for `archived_reported_posts` — out of scope here.
- No admin UI/RPC to read the archive — flagged previously as a possible follow-up, not part of this change.

## Testing

Manual SQL walkthrough: report a post, edit it, have a second reporter report it, delete it, confirm `archived_reported_posts.reports` contains two distinct `reported_content_snapshot` values (pre-edit and post-edit), not the same (edited) content twice.

No iOS app code changes are required — `report_content` and the deletion path are both server-side RPCs/triggers already called exactly as before from `SupabaseBoardService+Moderation.swift`. A full iOS build will be run after the migration to confirm nothing broke.
