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

## 1. BoardStore observation churn — partially fixed, one part genuinely needs on-device verification
- **Fixed:** `mergeWeekPosts` was building the incremental proxy dict by hand
  and then discarding that work with a full `rebuildCaches()` call (which
  redundantly rebuilt proxies again, plus reindexed profiles/boardWeeks that it
  never touched). Now calls only `rebuildPostsIndex()`, which is all that's
  actually needed after appending posts.
- **Still deferred, and deeper than it first looked:** `setReaction` /
  `setCommentVote` optimistic apply goes through `patchPostInWeekCache`, which
  mutates `postsByWeek` and `postsByID` on every single reaction/vote (not just
  the whole `posts` array). Those two dictionaries are also what
  `PostDetailView.livePost` (via `feedPost(id:)`) and `ArchiveCalendarView`'s
  counts (via `posts(for:)`) read for their *live* reaction-count display — so
  this isn't a "just read a different property" fix. Decoupling the per-post
  count path so only the `PostStateProxy` updates (which is what `FeedGridCard`
  already observes) means re-plumbing `PostDetailView` and `ArchiveCalendarView`
  to read counts from the proxy too, then verifying on-device that reaction
  counts still update correctly in both places. Do this on a branch with a
  physical device/simulator, not blind.

## 2. Auth-failure alert dedup (maintainability)
`SignInView`, `DeleteAccountView`, `AccountManagementSettingsView` repeat the
`authFailureMessage` + `onChange` + `presentableErrorAlert`-clear block. A shared
modifier is non-trivial because these views multiplex `alertError` for other
error sources too — extract carefully and verify alert behavior on each screen.

## 3. SettingsView split (maintainability)
`Views/Settings/SettingsView.swift` bundles the haptics/board-preview feature
(`boardPreview`, `shakeAndVibrate`, `ZigZagMark`, `PreviewCard`) with the settings
form. Extract to `SettingsHapticsPreview.swift` — but it threads `@State`
(rotations, shake trigger), so verify the preview still animates.

## 4. OnboardingProgressBar namespace (verify, then maybe delete)
`Views/Onboarding/OnboardingProgressBar.swift` uses a `NamespaceWrapper` +
`matchedGeometryEffect` so the bar can animate across steps. Each step view
instantiates a *separate* bar, so confirm on-device the cross-step transition
actually fires. If it doesn't, the namespace apparatus is inert and can be cut.
