# Client-Side Cache & Speedup — Design

## Context

`BoardStore` is currently fully in-memory and non-persistent per session: every cold launch re-fetches the active board (posts, profiles, reactions) from Supabase before rendering, `ProfileView` fetches Pop Score live in a view-local `@State` on every visit, `PostDetailView` fetches its comment thread live every time, and `NotificationSettingsView` holds settings as view-local `@State` fetched fresh on every visit — none of it is cached across navigations or relaunches. Images are the exception: `OnBoardImagePipeline` already gives Nuke a capped memory + disk cache, so avatar/thumbnail loading is not part of this work.

`BoardSnapshot` (`BoardService.swift`) already exists as the natural unit for a cached board — `{ week, posts, profiles, userReactions }` — and `BoardStore.refresh(for:)` already gates its loading spinner on a `hasCachedFeed` check. That means hydrating `BoardStore`'s in-memory state from a disk cache *before* `refresh(for:)` runs makes the existing spinner-skip logic work with no changes to `refresh(for:)`'s own gating.

## Goal

Reduce visible loading spinners across the app (cold launch, opening a profile, opening a post, opening notification settings) by caching already-fetched data and revalidating in the background, without adding real offline support — the app still requires network for any *new* data, this is purely about not re-showing a spinner for data already seen this session or a prior one.

## Non-goals

- No offline read/write support. Network is still required for anything not already cached.
- No disk persistence for archived-week content. Archives are opened far less often and are less latency-sensitive; within-session revisits are already fast today via `BoardStore.apply()`'s existing posts-merge behavior, and Phase 2's prefetch (below) applies to archived posts for free since they render through the same `PostDetailView`. Only the active week's snapshot persists to disk.
- No change to `ProfileView`'s live `isFollowing` check — it deliberately re-queries on every visit rather than trusting a cached `followedUserIDs` set, specifically so a stale local value can't flip "Following" back to "Follow". This is a documented, intentional exception, not an oversight.
- No true multi-writer conflict resolution for notification settings. It's a single-row-per-user upsert with no concurrent-writer scenario (RLS-scoped to `auth.uid()`); "server wins" just means any server-confirmed value always overwrites a local optimistic guess, which the existing reaction stale-guard pattern already achieves.

## Design

### 1. `CacheEnvelope` — one disk cache, one file

A new `Codable` struct holding everything cached to disk:

```swift
struct CacheEnvelope: Codable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let cachedAt: Date
    let boardID: UUID
    let snapshot: BoardSnapshot
    let archivedWeeks: [BoardWeek]
    let popScores: [UUID: [Reaction: Int]]
    let comments: [UUID: CommentThread]
    let notificationSettings: NotificationSettings?
}
```

`BoardSnapshot` gains `Codable` conformance (trivial — every member is already `Codable`). One JSON file in Application Support, matching the "cap it, overwrite it" simplicity of `OnBoardImagePipeline`'s disk cache rather than a generic per-entity-type cache or a SwiftData model graph — this app doesn't need real offline persistence, relational queries, or migrations, and a second schema to keep in sync with Supabase's is a documented risk in this codebase (the snake_case `CodingKeys` bug already bit `FollowRow`/`TagRow` twice).

New `BoardStore+DiskCache.swift`:
- `hydrateFromDiskIfNeeded(boardID:)` — reads the file if present, checks `schemaVersion` matches, checks `envelope.boardID == boardID` (a board switch must not hydrate a different board's stale cache), then applies `snapshot`/`archivedWeeks` via the existing `apply(_:incomingArchivedWeeks:)` and populates `popScores`/`comments`/`notificationSettings`.
- `persistToDisk()` — builds an envelope from current state and writes it. Fire-and-forget (spawned as a background `Task`, errors swallowed) — a failed write only costs a future cold-launch spinner, never correctness, since the next successful `refresh`/mutation will try again.
- `clearDiskCache()` — deletes the file. Called on sign-out.

### 2. Wiring into `BoardStore`

- `refresh(for:)` calls `hydrateFromDiskIfNeeded(boardID:)` before its existing `hasCachedFeed` check, only if not already warm in memory. A warm hydration makes `hasCachedFeed` true "for free" — `isLoading` never flips, no changes needed to that gating logic itself.
- After a successful `apply(...)` inside `refresh(for:)`: `persistToDisk()`.
- `BoardStore+Moderation.swift`'s `block`/`unblock`: also call `persistToDisk()` after resolving. Relying solely on the next `refresh()` would leave stale (unblocked) content on disk if the app is force-quit right after blocking someone.
- Sign-out path: calls `store.clearDiskCache()`. A cached board/profile/settings blob must never leak into a different account signing into the same device.

### 3. Pop Score moves into `BoardStore`

`popScores: [UUID: [Reaction: Int]]` becomes store-owned state (was `ProfileView`-local `@State`). `BoardStore+Profiles.swift` gains:
- `popScore(for userID: UUID) -> [Reaction: Int]?` — synchronous read.
- `refreshPopScore(for userID: UUID) async` — today's fetch-or-locally-aggregate logic, relocated from `ProfileView`'s `.task`, updates `popScores[userID]` and triggers `persistToDisk()` when it changes.
- `prefetchPopScore(for userID: UUID)` — no-op if already warm, otherwise fires `refreshPopScore` in a background `Task`.

`ProfileView` drops its local `popScore`/`isLoadingPopScore` `@State` and reads/revalidates through the store instead.

### 4. Prefetch on post-detail open, not feed scroll

Post authors are already backfilled into `profiles` as part of every normal load (`BoardStore+Refresh.swift`'s `loadMissingPostAuthorProfiles`/`loadMissingCommentAuthorProfiles`), so `Profile` itself is essentially always already warm by the time a post is opened — there is nothing to prefetch there. Pop Score is the one thing still fetched lazily and worth prefetching. `PostDetailView` gains a single `.onAppear`/`.task` call to `store.prefetchPopScore(for: post.authorId)`, so it's already resolved by the time (if ever) the user taps through to the author's profile. No feed-scroll prefetch hook is added — a scoped, intent-driven trigger (a tapped-into post) is cheaper and better-targeted than warming every author whose card merely scrolls into view.

### 5. Comments join the same cache

`commentsByPostID` is already preserved in memory across a session (`BoardStore.apply()`'s merge behavior), it just doesn't survive a relaunch. Added to `CacheEnvelope` as `comments: [UUID: CommentThread]` — same mechanism as everything else, no new code path. `PostDetailView` reads cached comments instantly if present, revalidates in the background.

### 6. Notification Settings — cached + optimistic + alerting

Today: `NotificationSettingsView` owns `@State settings`/`isLoading` independently of `BoardStore`, fetches fresh on every visit (spinner every time), and a failed save silently re-fetches from the server with no user-facing indication the toggle didn't stick.

Changes:
- `NotificationSettings?` joins `CacheEnvelope` and becomes `BoardStore`-owned state, hydrated from disk like everything else. `NotificationSettingsView` reads `store.notificationSettings` directly; the loading spinner only shows if that's `nil` (a true first-ever load with no cache at all). Every other visit paints instantly with a background revalidation.
- Saving mirrors `BoardStore+Reactions.swift`'s existing optimistic pattern exactly: mutate state synchronously first, a single in-flight sync `Task` that supersedes itself on rapid toggles, a stale-guard before rolling back (only roll back if the current value still equals what was optimistically set, so a failed old request can't clobber an even-newer local change). On failure: roll back **and** surface an alert, using the `PresentableAlertError` + `.presentableErrorAlert(...)` idiom every other Settings screen already uses — not `BoardStore.loadError`, which is semantically about board-loading failures, a different concern that shouldn't share a property with "your notification toggle didn't save."
- "Server wins on conflict" requires no new logic: any server-confirmed value (background revalidation or a failed-save refetch) always overwrites the local optimistic guess outright, identical to how reactions already behave.

### 7. Phase 3 — denormalized Pop Score (server-side, separate from the client cache)

A Supabase migration adding a trigger-maintained aggregate (exact shape — a `profiles` column vs. a small counts table — deferred to implementation time) so `fetchUserReactionCounts` reads a maintained value instead of aggregating live. `SupabaseBoardService.fetchUserReactionCounts(for:)`'s implementation changes; its signature and every call site stay identical. This is independent of and does not block the client cache work — it just makes the thing being cached cheaper to compute. Because it's a schema/trigger change to the live Supabase project, it will be proposed as its own migration and applied only after explicit confirmation, separate from the client-side implementation.

## Error handling

One rule throughout: **reads that revalidate already-cached data fail silently** (the user already has something on screen — matches the existing `// Failed silently for now` convention for Pop Score); **writes that fail always roll back and surface an alert** (reactions today, notification settings after this change).

Disk-cache specific:
- Any decode failure (corrupt JSON, mismatched `schemaVersion`) is treated as a plain cache miss — delete the file, fall through to the normal network-loading path. Never crash on a bad cache file, never partially apply a malformed envelope.
- Disk write failures (disk full, sandbox issue) are swallowed silently — a failed write only costs a future cold-launch spinner, never correctness.

## Testing

- `CacheEnvelope` encode/decode round-trip, including old-shape/partially-populated envelopes (all cached fields beyond the core snapshot should decode safely if missing) and a deliberately mismatched `schemaVersion` (must be treated as a miss, never attempt a partial decode).
- `hydrateFromDiskIfNeeded`: given a fixture envelope on disk, confirms `hasCachedFeed` becomes true and `isLoading` never flips to `true`, using this repo's existing mock-service test conventions.
- Notification settings optimistic save + rollback + alert: force `updateNotificationSettings` to throw, assert the toggle reverts and an alert is set.
- Stale-guard: two rapid toggle flips where the first fails after the second already landed — assert the first failure's rollback does not clobber the second (newer) value.

## CLAUDE.md addition

A new section documenting: one envelope/one file for all cached entities (adding a new cached type is one new Optional field, not a new mechanism); any decode failure is a cache miss, never a crash; `schemaVersion` bumps only when an existing field's *meaning* changes, not when adding new Optional fields; sign-out and every mutating action (block/unblock/reaction/comment/settings save) must explicitly call the persist/clear functions rather than relying on the next natural refresh to catch it; the `isFollowing` check is a documented, deliberate exception that must stay uncached; and the read-vs-write failure rule (reads fail silently, writes always alert and roll back).
