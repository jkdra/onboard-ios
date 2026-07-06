# TODO — deferred performance / refactor work

Historical log of the QC/perf pass. All items from the original list are now
resolved.

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

## ~~3. Auth-failure alert dedup~~ — DONE
Extracted `AuthFailureAlertModifier` (`.authFailureAlert(auth:error:)`) and
applied it to `SignInView`, `DeleteAccountView`, `AccountManagementSettingsView`,
replacing the identical `authFailureMessage` + `onChange` +
`presentableErrorAlert`-clear block in each. Safe despite those views also
writing other errors into the same `alertError` binding — the modifier only
reacts to `auth.state == .failed` and doesn't care who else populates it.

Bundled with this: unified the domain error types under a new
`PresentableDomainError` protocol (`AuthError`, `OnboardingError`,
`BoardServiceError` all conform), collapsing `PresentableAlertError.init`'s
three copy-pasted branches into one and giving `BoardServiceError` a real
`recoverySuggestion` for the first time. Any future domain error gets full
alert treatment by conforming to one protocol — no changes to
`PresentableAlertError` needed.

This surfaced a latent, unrelated build issue: the project sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which silently conflicted with
`LocalizedError`'s `nonisolated` requirements once these extensions took on
real protocol conformance. Fixed by marking the relevant properties
`nonisolated` explicitly.

## ~~4. SettingsView split~~ — DONE
Extracted `SettingsHapticsPreview.swift` (the board-mockup/haptic-shake demo:
`boardPreview`, `shakeAndVibrate`, `ZigZagMark`, `PreviewCard`) out of
`SettingsView.swift` (420 → 235 + 213 lines). It's fully self-contained via its
own `@AppStorage` reads (same UserDefaults keys as the toggles/slider that stay
in `SettingsView`, kept in sync automatically) — no threading needed. Tested
on-device: preview persists and animates correctly.

## ~~5. OnboardingProgressBar namespace~~ — REMOVED
On-device testing showed the bar animated its fill correctly but the whole bar
also visibly jumped between steps — both at once. Traced the cause:
`matchedGeometryEffect` was fighting the `NavigationStack` push transition
(which slides the whole screen as a rigid block while the effect independently
tries to reposition the bar) — a known-bad combination. The fill animation
(`onAppear`/`onChange(of: step)`) was always self-contained and independent of
the namespace, so removing `NamespaceWrapper`/`OnboardingNamespaceKey` and its
injection in `OnboardingCoordinator` couldn't lose it, and removes the one
thing that was causing the jump.
