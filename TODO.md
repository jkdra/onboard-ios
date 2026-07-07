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

## ~~6. BoardStore split~~ — DONE
665 → 448 lines. Classified every private property by actual read/write
coupling before splitting anything — the core caching cluster (`postsByWeek`,
`postsByID`, `profileIndex`, `postProxies`, feed-items cache) is genuinely
tangled (`rebuildCaches`, `apply`, `mergeWeekPosts`, `feedItems(for:)`,
`profile(id:)` all reach into it), and splitting it out would've forced
widening it all past `private` for organizational tidiness alone — Swift
extensions can't hold stored properties, so any method that moves to a new
file needs its backing state accessible from there. Left that cluster fully
private in the core file.

Extracted instead:
- `BoardStore+Refresh.swift` — network refresh, archive loading/LRU, comment
  fetches, notification settings. Archive eviction now goes through two new
  narrow methods on `BoardStore` (`cachedPostIDs(inWeek:)`,
  `removeProxies(for:)`) instead of touching `postsByWeek`/`postProxies`
  directly, so those stayed private. Only real widening: the refresh-task
  trio, `cachedArchiveWeekIDs`, and the `isLoading`/`accessibleBoards`
  setters — single-workflow bookkeeping, not shared caching structures.
- `BoardStore+Lookups.swift` — `currentUser`, `canEdit`/`isOwned`,
  `canInteract`, `comments(for:)`, `mutateComments`. Zero widening needed;
  none of it touches a raw private dict.

Also found and fixed two real bugs while auditing this:
- `clearFeedItemsCache()` was silently wiping `postsByID` (an unrelated
  index) as a side effect of a function named for a much smaller cache —
  removed.
- That side effect was the *only* thing keeping `resetForSignOut()` from
  leaking stale cross-session data — `postsByWeek`, `profileIndex`,
  `boardWeeksByID`, and `archivedWeeks` were never actually rebuilt on
  sign-out. Fixed by calling `rebuildCaches()` directly.
- `boardWeeksByID` itself was fully dead (written every rebuild, read
  nowhere) — removed. `rebuildBoardWeeksIndex` renamed `rebuildArchivedWeeks`
  since that's all it does now.

## ~~7. SignInView split~~ — DONE
598 → 482 lines (+132 in a new file). Same classification approach as the
`BoardStore` split: checked what `@State` each cluster actually touches before
assuming a boundary exists. Most of the file — form layout, credential block,
primary button, and the phone/email/OTP/password helpers — is one tangled
flow that all shares `credentialMode`/`phoneNumber`/`emailAddress`/`password`/
`otpCode`/`otpSent`/`submittedDestination`/`resendCooldown`, so (per the same
"don't force widening for tidiness alone" rule from the BoardStore split) it
stays together.

The one genuinely separable piece was Apple/Google sign-in — it never touches
any of that credential state, only `auth`/`network`, `resolvingProvider`/
`appleFlowInFlight`/`alertError`/`appeared`, and `presentAlert`. Extracted to
`SignInView+Social.swift`. Required widening those specific properties/the
`auth`/`network` environment values from `private` (same extension-can't-hold-
stored-properties constraint as before) — nothing else.

Also applied a perf tweak while in the area: the new `AnimatedLogoBackgroundView`
(added for the sign-in screen's aesthetic) ran its tiled-logo `Canvas` redraw
via `TimelineView` at 60fps continuously while on screen. Dropped to 30fps
(`minimumInterval: 1.0/30.0`) — the drift is slow enough (15pt/sec) that the
rate change is imperceptible, but it halves the recurring per-frame tile-draw
cost (~150-200 `draw()` calls/frame) for as long as the sign-in screen is up.

## 8. Backend: `get_active_board_week`/`maintain_board_weeks` missing board-membership check (deferred, low severity)
Found during the Supabase QC pass (see chat history, not a migration). Both
are callable by any signed-in user for *any* `board_id`, not just the
caller's own — a user could view week-timing metadata or trigger a
maintenance no-op for a board they're not a member of. Real severity is low:
`maintain_board_weeks`'s rollover is internally time-gated
(`if now() >= ends_at`), so there's no way to force an early rollover, only
an early metadata read. Not fixed because it needs to know how onboarding's
board-access sequencing works (does a user have a `board_members` row before
they're allowed to call this?) to avoid breaking that flow — needs
investigation, not a blind fix.
