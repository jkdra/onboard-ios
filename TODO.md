# TODO — deferred performance / refactor work

Items intentionally deferred because they need a live device, two accounts, or
a production schema migration to verify safely. Ranked by value.

## ~~1. Realtime reactions subscription filter~~ — REMOVED, not fixed
Decided the feature wasn't worth its cost for a weekly-cadence board (not a live
chat): `ReactionRealtimeListener`, `ReactionRealtimeChange`/`Parser`,
`BoardStore+Realtime.swift`, and all listener wiring in `BoardStore`/`RootView`
are deleted. Replaced with pull-to-refresh (existing) + foreground refresh
(existing) + a silent ~45s poll in `ContentView` while the feed is visible
(`BoardStore.refresh(for:)` already coalesces concurrent calls, so polling it is
cheap). See CLAUDE.md's Database section for the current freshness model.
Confirmed working: reactions still apply/persist correctly post-removal.

## ~~2. BoardStore observation churn~~ — mostly done
- **Fixed:** `mergeWeekPosts` no longer discards its incremental proxy update
  with a full `rebuildCaches()`; calls only `rebuildPostsIndex()`.
- **Fixed:** `PostDetailView.livePost` now reads through `postProxies[id]`
  (same pattern `FeedGridCard` uses) instead of `postsByID`, so viewing a post
  no longer re-evaluates on every *other* post's reaction/vote. Built and
  verified reactions still work correctly end-to-end.
- **Left as documented residual, not a bug:** `ArchiveCalendarView`'s per-week
  post count still reads `postsByWeek` directly. There's no per-week proxy to
  switch to, and it's a low-traffic screen (Archive), so introducing a new
  count-cache just for one badge wasn't worth it. If this screen ever gets
  busier, the fix is a `postCountByWeek: [UUID: Int]` cache invalidated only
  when posts are added/removed (not on reaction taps).

## 1. Auth-failure alert dedup (maintainability)
`SignInView`, `DeleteAccountView`, `AccountManagementSettingsView` repeat the
`authFailureMessage` + `onChange` + `presentableErrorAlert`-clear block. A shared
modifier is non-trivial because these views multiplex `alertError` for other
error sources too — extract carefully and verify alert behavior on each screen.

## ~~2. SettingsView split~~ — DONE
Extracted `SettingsHapticsPreview.swift` (the board-mockup/haptic-shake demo:
`boardPreview`, `shakeAndVibrate`, `ZigZagMark`, `PreviewCard`) out of
`SettingsView.swift` (420 → 235 + 213 lines). It's fully self-contained via its
own `@AppStorage` reads (same UserDefaults keys as the toggles/slider that stay
in `SettingsView`, kept in sync automatically) — no threading needed. Built
clean; **still needs**: open Settings on-device and confirm the preview still
shakes/animates and the haptics toggle still triggers it.

## 3. OnboardingProgressBar namespace (verify, then maybe delete)
`Views/Onboarding/OnboardingProgressBar.swift` uses a `NamespaceWrapper` +
`matchedGeometryEffect` so the bar can animate across steps. Each step view
instantiates a *separate* bar, so confirm on-device the cross-step transition
actually fires. If it doesn't, the namespace apparatus is inert and can be cut.
