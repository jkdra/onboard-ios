# TODO — deferred performance / refactor work

Items intentionally deferred from the QC/perf pass because they need a live
device, two accounts, or a production schema migration to verify safely. Ranked
by value.

## 1. Realtime reactions subscription filter (highest value — scaling cost)
`Supabase/ReactionRealtimeListener.swift` subscribes to **all** rows of the
`public.reactions` table with no filter; `BoardStore+Realtime.swift` then does an
O(n) scan and discards changes for posts not in the current week. Every reaction
on every board streams to every online client — cost scales with total app
activity, not what the user is viewing.

Blocked on: the `reactions` table has **no `board_week_id`** column. Requires
(a) a migration adding `board_week_id` + backfill from `posts`, (b) setting it on
the reaction insert path, (c) re-architecting the listener to filter
`board_week_id=eq.<week>` and re-subscribe when the active week changes.
Do on a branch; verify live reaction updates + week-switching before prod.

## 2. BoardStore observation churn (perf)
- `setReaction` / realtime writes mutate `posts[index]` directly — `posts` is a
  feed-wide `@Observable` array, so every reaction (local or remote) invalidates
  observers of the whole array (e.g. `ContentView`'s `store.posts.isEmpty`),
  partially defeating the per-card `PostStateProxy` design.
- `mergeWeekPosts` / `apply` call the full `rebuildCaches()` (which reassigns the
  whole `postProxies` dict) on every archive-week merge, reindexing/reallocating
  proxies for all loaded posts.
Fix: route the per-reaction count path through the index/proxy only; use
incremental merges instead of full rebuilds. Needs on-device verification that
feed counts still render correctly.

## 3. Auth-failure alert dedup (maintainability)
`SignInView`, `DeleteAccountView`, `AccountManagementSettingsView` repeat the
`authFailureMessage` + `onChange` + `presentableErrorAlert`-clear block. A shared
modifier is non-trivial because these views multiplex `alertError` for other
error sources too — extract carefully and verify alert behavior on each screen.

## 4. SettingsView split (maintainability)
`Views/Settings/SettingsView.swift` bundles the haptics/board-preview feature
(`boardPreview`, `shakeAndVibrate`, `ZigZagMark`, `PreviewCard`) with the settings
form. Extract to `SettingsHapticsPreview.swift` — but it threads `@State`
(rotations, shake trigger), so verify the preview still animates.

## 5. OnboardingProgressBar namespace (verify, then maybe delete)
`Views/Onboarding/OnboardingProgressBar.swift` uses a `NamespaceWrapper` +
`matchedGeometryEffect` so the bar can animate across steps. Each step view
instantiates a *separate* bar, so confirm on-device the cross-step transition
actually fires. If it doesn't, the namespace apparatus is inert and can be cut.
