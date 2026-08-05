# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

On Board is a campus bulletin board iOS app built with SwiftUI + Supabase. Students join a weekly board and post under their handle, react, and comment. It is **not** an anonymous app: posts are authored by a handle with a profile, avatar, and follow graph. Authorship is merely quiet on the feed grid — cards show a timestamp, not a name — but the opened post shows who wrote it and links to their profile. New boards open every Monday at midnight.

**Core functions:** per-campus weekly boards (open Monday, cleared at the next reset) shown as a tone-colored masonry feed; handle + profile identity with avatars, following, and a "Pop Score"; posts with optional images and tags; four reactions (like / hug / laugh / spark) and threaded comments; campus-email verification; an invite-gated waitlist with a viral referral ladder (instant invites skip it); push notifications; a weekly archive; and expected-graduation collection (alumni-only boards are planned, not yet built). A mascot, **The Host** (the app icon with a face), narrates the post-admission welcome + pledge.

## Associated Projects

On Board spans several sibling repos under `On Board/` (this one is `onboard-ios/`, the feature-complete reference client). Each sibling has its own CLAUDE.md — read it before working across the boundary.

- **`../onboard-android/`** — the Android port (Kotlin, Material 3, monochrome brand). Tracks this iOS app as the spec; a port, not a replica.
- **`../onboard-web/`** — the marketing site (Next.js + Tailwind + Supabase) at onboardapp.org: landing/waitlist, changelog (auto-pulled from the App Store), and the public privacy/terms pages.
- **`../onboard-admin/`** — the admin / moderation portal (Next.js 16, deployed via OpenNext on Cloudflare).
- **`../supabase/`** — the shared Supabase backend (Postgres migrations + edge functions) every client talks to. The `supabase/` folder inside this repo is a gitignored working copy of the same schema; the sibling is the canonical home.
- **`../host-chat/`** — an early React + Vite prototype (name-associated with The Host); not yet documented.

## Build & Test Commands

```bash
# Build
xcodebuild -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5"

# Run all tests (disable parallel testing to avoid clone crashes)
xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO

# Run a single test (uses Swift Testing, not XCTest)
xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/OnboardingStoreTests/refreshMarksCompleteForSampleAppleUser"
```

> **Destination gotcha:** if `name=iPhone 16 Pro,OS=18.5` fails with "Unable to find a
> device matching the provided destination specifier", there are duplicate simulators
> with that name. List them with `xcrun simctl list devices available` and pass a
> specific `-destination "id=<UDID>"` instead.

The app targets iOS 18+ as its minimum deployment target. iOS 26 APIs (e.g. `glassEffect`) are used where available via `#available(iOS 26.0, *)` guards with fallbacks for older OS versions.

No secrets are required to build. The app runs fully offline with `MockAuthService` and `MockOnboardingService` when `Secrets.xcconfig` is absent — `Configuration/Project.xcconfig` pulls it in with `#include?`, which is a no-op when the file is missing. To enable live Supabase, create a gitignored `Secrets.xcconfig` at the repo root defining `SUPABASE_ANON_KEY` (and `GOOGLE_CLIENT_ID` for Google sign-in). There is no `Secrets.xcconfig.example`, and `SUPABASE_URL` is **not** read from it — see Configuration below.

> **Driving the app in mock mode from the CLI** (e.g. for UI tests): temporarily remove
> `Secrets.xcconfig` — that alone flips it to mocks. Do **not** set
> `XCODE_RUNNING_FOR_PREVIEWS=1` on a real app run; SwiftUI then renders an empty view
> hierarchy (0 elements). To skip sign-in, seed `MockAuthService`'s persisted session via
> `NSArgumentDomain`: pass `-mock.auth.session "<hex-of-JSON-AuthSession>"` as a launch
> argument for `SampleProfileID.maya`, whom `MockOnboardingService` reports `.complete`.

> **Xcode can report errors for code that isn't there — `xcodebuild` is ground
> truth.** Hit twice on 2026-08-02, from two unrelated causes, each costing real
> time before anyone checked the CLI:
> 1. **Unsaved/stashed work.** SourceKit was still diagnosing buffers from a
>    `git stash`ed branch — errors named types (`PromotedSlot`), files
>    (`Styling/Font/ButlerFont.swift`) and line numbers that existed in *no* file
>    on disk in the checked-out branch.
> 2. **A broken index after Clean Build Folder.** The tell is *system* modules
>    failing: `No such module 'UIKit' / 'XCTest' / 'Testing'`. Nothing in this
>    repo can break UIKit — that means SourceKit has no compiler arguments at all,
>    and every "Cannot find X in scope" below it is downstream noise. A CLI build
>    does **not** repair it (Xcode holds its own in-memory state); ⌘B inside
>    Xcode, or quitting and reopening, does.
>
> Before debugging any Xcode error list, run
> `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build`.
> If that says `** BUILD SUCCEEDED **`, the code is fine and the problem is the IDE.
> Also check for orphaned DerivedData pointing at deleted worktrees:
> `for d in ~/Library/Developer/Xcode/DerivedData/On_Board-*; do plutil -extract WorkspacePath raw "$d/info.plist"; done`

> **Simulator launch-screen caching gotcha:** the Simulator (via SpringBoard) can cache
> a stale rendering of `LaunchScreen.storyboard`'s launch image across a plain
> `simctl install`/reinstall of the app — editing an asset in `LaunchHost.imageset` and
> reinstalling can keep showing the *old* image indefinitely. A full `simctl shutdown` +
> `simctl boot` of the simulator (not just terminating/relaunching the app) clears it.
> Don't mistake this for the fix not having worked — verify the source PNGs directly
> (e.g. via Python/PIL pixel inspection) before assuming a code or asset change failed.

## Architecture Overview

### State Management
All major stores are `@Observable @MainActor` classes, injected as environment objects at the root:
- **AuthStore** — auth state machine, session management, multi-provider linking
- **BoardStore** — weekly posts, reactions, comments (in-memory, non-persistent per session)
- **OnboardingStore** — onboarding flow progression and step state
- **NetworkMonitor** — wraps `NWPathMonitor`

`NotificationService` is a `@MainActor` singleton (not injected as an environment object) that handles APNs registration, device token upload, and `last_seen_at` tracking. It is driven directly from `On_BoardApp.swift`.

### Service Layer (Protocol + Factory Pattern)
Every backend interaction is behind a protocol so mocks require zero Supabase configuration:

| Protocol | Live Impl | Mock Impl | Factory |
|---|---|---|---|
| `AuthService` | `SupabaseAuthService` | `MockAuthService` | `AuthServiceFactory.make()` |
| `BoardService` | `SupabaseBoardService` | _(none — BoardStore guards nil)_ | `BoardServiceFactory.make()` |
| `OnboardingService` | `SupabaseOnboardingService` | `MockOnboardingService` | `OnboardingServiceFactory.make()` |

The entry point (`On_BoardApp.swift`) selects mock vs. live via `AppLaunchContext`: `isPreview` forces mocks, and each factory *also* falls back to its mock when `AppConfiguration.isSupabaseConfigured` is `false` (i.e. no `Secrets.xcconfig`). So a build missing the anon key runs entirely on mock data without complaining.

### Optimistic Updates
`BoardStore+Interactions.swift` applies all mutations (reactions, post creation, comments) locally first, then syncs to Supabase. On error it rolls back and surfaces the error. Never skip the rollback path when adding new mutations.

**In-flight supersession**: any optimistic mutation a user can fire twice in quick succession (reactions, comment votes, comment edits, notification-settings, follow/unfollow) keeps a per-key `Task` in `BoardStore` (`reactionSyncTasks`, `commentVoteSyncTasks`, `commentEditSyncTasks`, `notificationSettingsSyncTask`, `followSyncTasks`) and cancels the prior one before starting a new one, checking `Task.isCancelled` before any rollback/re-assertion runs. Without this, a rapid follow→unfollow→follow (or any repeated toggle) can let an earlier request's completion invert state that's already moved on — this shipped as a real bug for follow/unfollow before the guard was added; any new toggle-style mutation needs the same pattern. `block`/`unblock` use a simpler variant — `blockOperationsInFlight: Set<UUID>` — since two different screens (`ProfileView`, `PostDetailView`) can each call `store.block(userID:)` for the same user; a second call while one's in flight is a no-op rather than a race, because these `throw` to their caller instead of routing through `loadError`.

**Patch, don't reload, after an insert that returns the real row**: `addComment` inserts an optimistic comment (temp UUID) locally, then `SupabaseBoardService.createComment` returns the confirmed `Comment` (via `.insert(...).select().single()`) so `BoardStore` can swap just that one node in the local tree — it used to call a full `loadComments` reload (two more RPCs, whole-thread rebuild) just to learn the server-assigned id. If you add a similarly-shaped "insert one optimistic thing, need its real id back" mutation, prefer returning the created row over reloading everything.

**Save-button double-tap guards**: `PostDetailView.saveEdits()` and `ProfileView.saveProfile()` each keep a local `isSaving*` flag (`isSavingEdits`, `isSavingProfile`) that both disables the toolbar Save button (`EditModeToolbarItems`'s `canSave`) and no-ops a second call while the first is still in flight — otherwise a double-tap fires two concurrent `updatePost`/`updateProfile` calls and whichever response lands last silently wins, discarding the other edit. `PhotoAttachmentController.uploadCropped` has the analogous problem for cancel-and-retry photo picks (pick A, crop, then before upload resolves pick B and crop) — it guards with an incrementing `uploadGeneration` token instead, since unlike Save it's not gated behind a single button.

**`loadComments` merge guard**: `loadComments` wholesale-replaces `commentsByPostID[postID]` with whatever the server returned — unlike the reaction/vote/follow sync tasks, it has no per-call generation token, because it isn't racing one specific other call, it's racing *anything* that might touch that post's comments while its fetch is in flight (which is on every post open, since it revalidates even an already-cached thread). `BoardStore.commentsLastLocallyMutatedAt: [UUID: Date]` (keyed by post) is stamped by every local comment mutation — centrally inside `mutateComments` for the ones that go through it, plus explicitly at `addComment`'s and `deleteComment`'s direct writes that bypass it. `loadComments` captures its own fetch's start time before the await and bails entirely (no comments, no votes, no persist) if that post was locally mutated more recently — the next post-open naturally re-fetches once nothing's in flight, so nothing is lost, just deferred one revalidation cycle. `BoardSwitchRaceTests.loadCommentsDoesNotClobberAConcurrentLocalEdit` (`On_BoardTests.swift`) pins this with `SlowBoardService`'s `slowCommentsPostID`/`releaseSlowComments()`. Any new mutation that writes `commentsByPostID` directly (bypassing `mutateComments`) needs the same stamp.

### Client-Side Cache
`BoardStore` persists a single `CacheEnvelope` (`BoardStore/CacheEnvelope.swift`) to disk via `BoardStore+DiskCache.swift`, after every successful board `apply()` and after any mutation that changes cached state (block/unblock, notification-settings save). `refresh(for:)` hydrates from this file before its `hasCachedFeed` check, so a warm cache skips the loading spinner entirely — no changes needed to `isLoading`'s existing gating. `hydrateFromDiskIfNeeded`'s read + decode runs off-main via `Task.detached` (a large cached feed's JSON is nontrivial to parse) — it's `async` for exactly this reason, so `refresh(for:)` `await`s it.

**`CacheEnvelope`'s Codable conformance is hand-written, not synthesized** (explicit `nonisolated init(from:)`/`encode(to:)`, same idiom as `Profile`/`NotificationSettings`) — this module defaults to MainActor isolation, so a plain `struct CacheEnvelope: Codable` gets a MainActor-isolated conformance that a Swift 6 build then refuses to use inside `Task.detached` (`main actor-isolated conformance ... cannot be used in @concurrent context`). Adding `Sendable` to the struct alone does not fix this. If you add a field, add it to the manual `CodingKeys`/`init(from:)`/`encode(to:)` too, not just the stored property.

**Adding a new cached entity**: add one field to `CacheEnvelope`, make it `Optional` (so older cache files still decode), and make sure whatever mutates it in `BoardStore` also calls `persistToDisk()`. Don't invent a second cache mechanism — one envelope, one file.

**Schema drift safety**: any decode failure (bad JSON, mismatched `CacheEnvelope.schemaVersion`) is treated as a cache miss — the file is deleted and normal network loading proceeds. Never crash on a stale/malformed cache file. Bump `schemaVersion` only when an existing field's *meaning* changes in a way old data would misrepresent — adding a new `Optional` field does not require a bump.

**Invalidation correctness**:
- Sign-out calls `clearDiskCache()` (wired into `resetForSignOut()`) — a cached board/profile/settings blob must never leak into a different account's session on the same device.
- Any mutation that changes what's cached (block, unblock, notification-settings save) calls `persistToDisk()` after resolving — don't rely solely on the next natural `refresh()` to capture it, since a force-quit in between would leave stale content cached.

**Known intentional exception — do not cache**: `ProfileView`'s live `isFollowing` check (`.task(id: profile.id)`) deliberately bypasses `followedUserIDs`/any cache and re-queries the server on every profile visit, specifically so a stale cached value can't flip "Following" back to "Follow". Don't fold this into the general cache-everything pattern.

**Read-vs-write failure rule**: background revalidation of already-cached data (Pop Score, comments, notification settings) fails silently — the user already has a value on screen. A failed *write* (a reaction, a notification-settings toggle, anything optimistic) always rolls back and surfaces an alert — never fail a save silently.

**Don't persist revalidation reads that didn't change anything**: `loadComments` and `refreshPopScore` run on nearly every post open, most of the time just reconfirming an already-cached value — `persistToDisk()` does a synchronous full-envelope encode + disk write, so calling it unconditionally on every fetch (rather than only when the fetched value actually differs from what's cached) is wasted work that scales with how much a session has cached. Both now diff against the previous value first and only persist on an actual change; a new revalidation-style read should follow the same guard rather than persisting unconditionally.

### Navigation Flow
```
RootView
  ├── auth.isSignedIn == false  →  SignInView
  └── auth.isSignedIn == true
        ├── onboarding.needsOnboarding  →  OnboardingCoordinator
        └── otherwise                   →  ContentView (Feed)
```

### Configuration
`AppConfiguration.swift` reads `SupabaseURL`, `SupabaseAnonKey`, and optionally `GoogleClientID` from the generated Info.plist. The source is `On-Board-Info.plist`, where:

- `SupabaseURL` is **hardcoded** to the production project URL — it does not come from `Secrets.xcconfig`.
- `SupabaseAnonKey` and `GoogleClientID` are `$(SUPABASE_ANON_KEY)` / `$(GOOGLE_CLIENT_ID)`, substituted from `Secrets.xcconfig` (included by `Configuration/Project.xcconfig`).

So the **anon key alone** decides live vs. mock: without `Secrets.xcconfig` it expands to an empty string, `AppConfiguration.isSupabaseConfigured` returns `false`, and the factories hand back mocks. (The property is `isSupabaseConfigured`; there is no `isConfigured`.)

### JSON Codecs — read this before adding any Supabase model
`SupabaseClientFactory` installs `BoardJSON.encoder` / `BoardJSON.decoder` on the client, which apply `.convertToSnakeCase` / `.convertFromSnakeCase`.

**Never write snake_case `CodingKeys` on a type that crosses PostgREST.** The failure is asymmetric and vicious: `convertToSnakeCase("following_id")` is a no-op, so *encoding still produces the right wire format*, while decoding camel-cases the incoming `following_id` to `followingId`, fails to find a CodingKey with that string, and throws `keyNotFound`. Writes land in Postgres; reads always throw. Paired with a swallowed `catch`, the feature looks half-dead while the data looks perfect.

```swift
struct Row: Decodable { let followingId: UUID }                          // ✅
struct Row: Decodable {                                                 // ❌ decode always throws
    let followingId: UUID
    enum CodingKeys: String, CodingKey { case followingId = "following_id" }
}
```

If you must declare `CodingKeys`, use bare cases with no raw values (as `NotificationSettings` does). This bug has shipped twice (`FollowRow`, `TagRow`); `FollowRowCodingTests` / `TagRowCodingTests` pin both directions.

### Deep Linking
Post sharing supports both a universal link (`https://onboardapp.org/post/<UUID>`, requires the `com.apple.developer.associated-domains` entitlement pointing at `applinks:onboardapp.org`) and a custom scheme fallback (`onboard://post/<UUID>`). Both are parsed in `On_BoardApp.swift`'s `onOpenURL`, which hands the post ID to `NotificationService.shared.setPendingPostID(_:)` — the same pending-post mechanism used by push notification taps. OAuth callback URLs and magic-link URLs pass through the same `onOpenURL` but are routed to Supabase's `client.auth.handle(url)` instead. Because magic-link/external sign-ins resolve silently in the SDK, `On_BoardApp.swift` also observes `client.auth.authStateChanges` and calls `auth.restoreSession()` on a `.signedIn` event the app didn't initiate interactively.

### Database
Supabase migrations live in `supabase/migrations/` (gitignored — the backend is deliberately kept out of the iOS repo). Board data is fetched via Supabase RPC functions (`get_active_board_week`, `fetch_posts_for_week`, `fetch_my_reactions_for_week`, `fetch_tags_for_week`). There is no realtime subscription for reactions/posts — the board is weekly-cadence, not live chat, so a Supabase Realtime channel wasn't worth its always-on connection and scaling cost (it had no server-side filter, meaning every reaction on every board streamed to every client). Freshness instead comes from pull-to-refresh, a foreground-triggered refresh (`RootView`'s `scenePhase` handler), and a silent ~45s poll in `ContentView` while the feed is on screen. `BoardStore.refresh(for:)` coalesces concurrent calls, so polling it repeatedly is cheap.

**Migration history (verified 2026-07-28):** remote ledger has 62 migrations, oldest `20260703000000_storage_cleanup`, newest `20260728180428_check_phone_exists`. The 2026-06-29 reconciliation baselines (`20260629081312_remote_schema`, `20260629120000_device_tokens_rls_initplan`) are **no longer in the remote ledger**; don't expect to find them. Pre-reconciliation files are preserved under `supabase/migrations/_archive_drift_2026-06-29/` — do not resurrect them. `supabase db pull` / `db push` work normally; add new changes as fresh timestamped migrations and push through a preview branch. Avoid hand-editing the remote migration ledger. (Note: this machine's local sibling `../supabase/` checkout is stale/nearly empty — the Supabase MCP tools against the live project are the authoritative source, not the local migrations folder.)

### UI Conventions
- **In-flight buttons** use `LoadingButtonLabel(_:systemImage:isLoading:)` (a spinner to the left of the title), paired with `.disabled(isLoading)` on the page — never swap the screen for a separate loading view. Spinner tint defaults to `systemBackground` (matches `.boardPrimary`); pass `spinnerTint: .accentColor`/`.primary` for non-filled buttons.
- **Keyboard dismissal:** attach `.keyboardDoneToolbar()` (adds a "Done" key accessory) and `.scrollDismissesKeyboard(.interactively)` to any screen hosting text input. Both route through `KeyboardDismisser.dismiss()` (see `Extensions/View+KeyboardDismiss.swift`), which resigns first responder app-wide — no per-field `@FocusState` plumbing needed.
- **Dismissing a sheet that still has a focused text field: resign the keyboard first, then dismiss.** `NewPostView`, `CommentComposerSheet`, and `SetPasswordView` all auto-focus a field on `.onAppear`; their Cancel/success dismiss paths call `KeyboardDismisser.dismiss()` immediately before `dismiss()`. Skipping this lets the sheet's own dismiss transition race the keyboard's hide animation on the same window — the next screen shown (e.g. a `PostDetailView` pushed right after) can inherit a stale keyboard-sized safe-area inset, visibly pushing its bottom-pinned content (like the reaction bar) up until something else forces a relayout. Intermittent by nature (it's a race), so "sometimes it comes back down, sometimes it doesn't" is the expected symptom, not a sign the fix didn't work. Any new sheet that auto-focuses a field needs the same one-line guard before every `dismiss()` call site.
- **Composed tap gestures:** a double-tap that coexists with drag/magnification gestures must use `SpatialTapGesture(count: 2)` (location + count in one recognizer) or a `.simultaneousGesture(TapGesture(count: 2))` — a plain `.onTapGesture(count: 2)` loses gesture arbitration and silently never fires.
- **Gesture priority near system controls:** a plain `.gesture()` layered over a `TextField`/other UIKit-bridged control loses arbitration to that control's own recognizers — a swipe/drag starting on the control itself (not just its padding) silently never fires. Use `.highPriorityGesture()` instead; it only claims the touch once its own recognition threshold (e.g. `minimumDistance`) is cleared, so taps/typing/cursor placement pass through untouched. See `CommentComposerBar.fieldCluster`'s swipe-to-expand.
- **Deferred gesture resolution after navigation:** single/double-tap disambiguation (`ExclusiveGesture` + `SpatialTapGesture(count:)`) carries the system's standard delay, and the zoom navigation transition below keeps a popped destination mounted through the pop animation — so a tap made right before backing out can resolve *after* the view is gone, acting on stale state (e.g. silently reopening a `fullScreenCover` on a screen the user already left). `DoubleTapHeart.swift` guards this with an `isPresentedOnScreen` flag (`true` on `.onAppear`, `false` on `.onDisappear`) checked before the gesture's effect runs. Any new tap-disambiguating or otherwise-deferred gesture handler on a pushed screen needs the same guard.
- **A raw gesture recognizer (`SpatialTapGesture`, `ExclusiveGesture`, drag, etc.) is invisible to VoiceOver** — its activation (double-tap) doesn't route into custom gesture recognizers the way it does into `Button`/`.accessibilityAction`. Any view whose only way to trigger an effect is a custom gesture (not a `Button`) needs an explicit `.accessibilityActions { Button("Name") { ... } }` alongside it, or a screen-reader user has literally no way to trigger that effect. `DoubleTapHeart.swift` exposes "Like"/"Unlike" and (when `onSingleTap` is set) "Open Photo" this way.
- **A control nested inside a `Toggle`'s label is generally unreachable by VoiceOver** — the row's own activation target wins over a child button. Keep any secondary interactive control (e.g. an "i" info button) as a sibling of the `Toggle` in an `HStack`, not inside its label closure. See `SettingsView`'s Profanity row.
- **A `.scaleEffect` used for an entrance/reveal animation needs an explicit `anchor`, not the `.center` default, when the content isn't centered.** Scaling around `.center` translates every pixel away from the midpoint as it grows — for top-leading-aligned content (e.g. a card's title text), that reads as the text visibly shifting during the "grow" instead of the card just fading/growing in place, worse the more/denser the content is (a longer, multi-line title shows it more than a short one). `BoardFeedView.masonryCell`'s entrance `.scaleEffect` anchors `.topLeading` (matching the card content's own alignment) for exactly this reason — a new scale-based reveal on non-centered content should anchor the same way.
- **Don't share a `matchedGeometryEffect`/`glassEffect` identity between a composite, self-painting view and an unrelated element.** If the target already paints its own material per-subview (e.g. `ReactionBar` paints glass per pill via `reactionBackground`), wiring an unrelated element's morph background to that same view's frame stacks a second full-width glass panel behind it — a double-glass/blurred-text landmine that's shipped more than once. If two elements need to visually morph into each other, the target must not already be painting its own material.
- **Auth → onboarding transition:** a fresh interactive sign-in keeps `SignInView` in place (form disabled, tapped button spinning) until status resolves; only a silent cold-launch `restoreSession` shows the covering loader (`OnboardingCoordinator.interactiveSignIn` gates this — interactive sign-ins pass through `.signingIn`, restore does not).
- **Onboarding progress bar:** `Views/Onboarding/OnboardingProgressBar.swift` is a plain view taking the step index — each step view instantiates it directly (`OnboardingProgressBar(step: 2)`). There is no shared `Namespace`, no `matchedGeometryEffect`, and no `EnvironmentValues.onboardingNamespace`. A new step view just adds its own `OnboardingProgressBar(step:)` with the right index.
- **Settings toggles:** use `Toggle(isOn:) { Text(title).fontStyle(.body) }` plus `.tint(.primary)`. Omitting the tint leaves the switch in the default accent green, which reads as subtly "off" next to the other settings screens.
- **Zoom navigation transitions** (feed card → post detail). In production exactly **one** `navigationDestination(for: BoardRoute.self)` exists — ContentView's; the ones in `ArchiveView` / `ArchiveCalendarView` are `#Preview`-only. It applies `.navigationTransition(.zoom(sourceID:in:))`, so four rules bind every feed card:
  1. **One namespace.** Sources must register in ContentView's `@Namespace`, threaded down via `EnvironmentValues.cardNamespace`. `BoardFeedView` is shared by the feed, `ProfileView`, and `ArchivedWeekView`; a source registered in any other namespace is invisible to the destination, the zoom resolves no source rect, and the card collapses toward zero on pop. Never pass a local `@Namespace` into `BoardFeedView`.
  2. **Source id is the `BoardRoute`, not `post.id`.** A pushed `ProfileView` shows this week's posts — the same ids as the still-alive feed beneath it. `.post` vs `.postFromProfile` keeps the two sources distinct. The route is both the `NavigationLink` value and the source id.
  3. **Nothing may transform the source from above.** An ancestor `.rotationEffect` / `.scaleEffect` makes the source's screen-space geometry a rotated quad, which `.zoom` can't represent. This *only* manifests on the interactive edge-swipe pop (which re-resolves source geometry every frame); the back button resolves it once and hides the bug. `GridCard` therefore applies `cardRotation` itself, beneath its own `matchedTransitionSource`; `BoardFeedView.masonryCell` rotates only the non-post cards.
  4. **The source frame must contain everything the card draws.** `.overlay` and `.offset` don't expand a view's frame, so the reaction sticker's 13pt overhang fell outside the source rect and was clipped mid-zoom. `GridCard` wraps the source in `.padding(16)` → `matchedTransitionSource` → `.padding(-16)`, growing the source rect while leaving the masonry footprint unchanged.

  > Debugging these: `XCUIElement.tap()` blocks until the app is idle, so XCUITest screenshots **always** land after the animation. Capture with `xcrun simctl io <udid> recordVideo` and decode with `AVAssetReader` — `AVAssetImageGenerator` snaps to sparse keyframes and silently returns the same frame.

  > **XCUITest tap delivery is currently broken under this Xcode (verified 2026-08-02).** Synthesized taps on SwiftUI elements silently do nothing — feed grid cards, the compose card, and the nav-bar ••• `Menu` trigger all fail, the last with an explicit `Automation type mismatch: computed Button from legacy attributes vs PopUpButton from modern attribute` (`SwiftUI.AccessibilityNode`). Reproduces identically on the iOS 18.5 and 27.0 runtimes, so it's the Xcode XCUITest layer, not a runtime or app regression — and not the perpetual-animation idle issue, which was ruled out separately (Reduce Motion changed nothing). Before writing any UI test that taps, check whether this still reproduces; prefer deep links (`simctl openurl`) or `-dev.*` launch arguments to reach screens without synthesized interaction. Full investigation log: `On BoardUITests/ReactionBarInsetUITests.swift`'s header.

### Push Notifications
Push is delivered via APNs using a `.p8` key stored as a Supabase Edge Function secret. The `send-notifications` Edge Function dispatches on a `trigger` string. Two families reach it:

**`pg_cron` jobs** (verified against `cron.job` 2026-07-10):

| Trigger | Schedule (UTC) | Audience |
|---|---|---|
| `monday-reset` | `30 14 * * 1` | Everyone |
| `re-engagement` | `0 17 * * 1-6` | Inactive 2+ days with unseen posts |
| `sunday-reengagement` | `0 19 * * 0` | Anyone with unseen posts |
| `clearing-soon` | `0 3 * * 1` | Everyone (body varies by unseen post count) |
| `new-posts-digest` | `*/15 * * * *` | Via `get_new_posts_digest_targets` (gated on `push_new_posts`) |

**Database triggers** calling `notify_push(trigger, payload)`, which `POST`s to the function:

| Trigger | Fires on | Gate |
|---|---|---|
| `reaction` | `notify_on_reaction` | `push_reactions` |
| `comment` | `notify_on_comment` | `push_comments` |
| `followed_post` | `trg_notify_on_followed_post` on `posts` | `push_followed_posts` + `push_notification_ledger` dedupe |

> **Every `notify_push` trigger name needs a matching `case` in the Edge Function's
> `switch`.** `followed_post` shipped without one for weeks: the DB trigger fired, the
> function hit `default:` and returned 400, and `notify_push` swallows exceptions — so it
> failed completely silently. Verify with
> `select notify_push('<trigger>', '{...}'::jsonb);` then read `net._http_response`.

**APNs host:** the function tries `api.push.apple.com` first, falls back to `api.sandbox.push.apple.com` on `BadDeviceToken`, and persists whichever host worked in `device_tokens.environment`. There is no `APNS_HOST` env var, and **no host change is needed for release** — dev, TestFlight, and App Store tokens all resolve automatically.

## Key Conventions

- **Adding a new auth provider**: touch `AuthProvider.swift`, `AuthService.swift` protocol, `SupabaseAuthService.swift`, and `MockAuthService.swift`. Both impls must stay in sync.
- **Unlinking or deleting an account with a linked Apple/Google identity**: revoke the provider token first, then unlink/delete — don't skip this, Apple/Google otherwise still consider the app authorized. Apple requires an authorization code (obtained via a fresh `AppleSignInCoordinator.requestAuthorization()` + `authorizationCode(from:)`) passed to `AuthStore.revokeApple(authorizationCode:)`, which calls the `revoke-apple` Supabase Edge Function. Google is simpler — `GoogleSignInService.disconnect()` is called locally (no server round-trip) from `SupabaseAuthService`'s unlink/sign-out paths. Both `AccountSecuritySettingsView` (unlink) and `DeleteAccountView` (delete) call the Apple revoke step before their respective `AuthStore` call.
- **Adding a new post/comment field**: update `Post.swift` / `Comment.swift`, `RemotePostRow.swift` (JSON decoding adapter), and the relevant Supabase RPC or table query in `SupabaseBoardService.swift`.
- **Every enum that crosses the Supabase wire must decode unknown values, never throw.** These are decoded inside arrays (`[RemotePostRow]`, `[UserReactionRow]`, `[UserCommentVoteRow]`, `[BoardWeek]`), so one unrecognized value fails the *entire* response — a tone added in a future build would blank the whole feed for every client that hadn't updated, for a week, with the content gone at the next reset. **Pick the fallback by semantics; there is no generic default:**
  - `PostTone` → deterministic known tone via `StableHash` (`stableFallback(for:)`).
  - `Reaction` / `CommentVote` → `UserReactionRow.type` and `UserCommentVoteRow.vote` carry a raw `String` and are **dropped** at mapping time with `compactMap`. Never map an unknown reaction onto a known one — it silently inflates that reaction's count.
  - `BoardWeek.Status` → `.archived` (read-only). Statuses get added to express new *restrictions*, not new permissions, and read-only never costs the user written work the way a rejected post would.
  - `OnboardingStep` → `.unrecognized`, routed to `OnboardingUpdateRequiredView`. The one case where the right degradation is "tell the user to update": `.complete` would admit someone who never onboarded, and any concrete step could trap them. It is **excluded from a hand-written `allCases`** because `OnboardingCoordinator.rank(_:)` and `OnboardingProgressBar` index off that list.
  - `AuthProvider` needs nothing — every wire path already goes through the failable `init?(supabaseProvider:)`; its `Codable` decode is only for the locally-persisted session.

  `WireEnumDecodingTests` pins all of it, including the `allCases` exclusion. `RemotePostRow.decodeReactionCounts` was already correct and is the pattern to copy.
- **Remote config lives in `Configuration/RemoteConfig.swift` and nowhere else.** It is the only file containing config key literals; call sites read typed accessors (`config.feedPollSeconds`), never strings. Every accessor falls back to the value that was compiled in, so a server returning `{}` behaves exactly like a build with no remote config — never add an accessor whose fallback makes the caller skip behavior it does today. Adding a key means: add it to the `get_app_config` allowlist migration, add a typed accessor with the current hardcoded value as its fallback, then read it at the call site. The RPC uses an explicit allowlist, **never `select *`** — `app_config` also holds server-only keys (`board_timezone` drives the cron reset) that would otherwise leak to anyone holding the shipped anon key.
- **Config is cached in `UserDefaults`, deliberately not in `CacheEnvelope`.** The envelope is cleared on sign-out and hydrated async by `BoardStore`; config must survive sign-out and be readable synchronously *before* sign-in, because the version gate and auth-flow flags matter precisely when signed out. A documented exception to the "one envelope, one file" rule, not a second cache for board data.
- **Every new feature is born behind a `FeatureFlag`, defaulted `false`.** Ship it inert on the normal release cadence and switch it on when ready — that is what decouples "the feature is done" from "Apple approved the build". Flags added retroactively for existing surfaces default `true`, since a flag's compiled default must always equal what the app already does. Bucketing is salted per flag (`RemoteConfig.bucket(_:salt:)`); without the salt the same unlucky cohort receives every staged rollout forever. Signed-out users bucket on `RemoteConfigStore.installIdentity`.
- **How a flag reaches its call site depends on what the call site is.** Three shapes, all in use: a *nilable namespace* (`ContentView.activeCardNamespace` for `zoomTransition` — one nil disables both the sources and the destination, and disabling only one end is worse than neither); an *`EnvironmentValue` defaulting to `true`* (`glassEffectsEnabled`, `photoAttachmentsEnabled`) for views, because `@Environment(RemoteConfigStore.self)` **traps** when the store is absent and would break every `#Preview` of the affected leaf views; and a *plain static* (`HostVoice.isEnabled`) for imperative engines read at call time rather than render time. Don't reach for a static on anything SwiftUI renders — a static isn't observable, so the server change wouldn't repaint.
- **How a flag reaches its call site depends on what the call site is.** Three shapes, all in use: a *nilable namespace* (`ContentView.activeCardNamespace` for `zoomTransition` — one nil disables both the sources and the destination, and disabling only one end is worse than neither); an *`EnvironmentValue` defaulting to `true`* (`glassEffectsEnabled`, `photoAttachmentsEnabled`, `enabledReactions`) for views, because `@Environment(RemoteConfigStore.self)` **traps** when the store is absent and would break every `#Preview` of the affected leaf views; and a *plain static* (`HostVoice.isEnabled`, `BoardStore.archiveWeekCacheLimit`) for imperative engines read at call time rather than render time. Don't reach for a static on anything SwiftUI renders — a static isn't observable, so the server change wouldn't repaint. That is exactly why `BoardPhase`'s posting-gate thresholds are still compiled: a gate that silently uses stale values is worse than one that can't move.
- **A model that isn't a `View` can't read the environment.** `ProfileDraft` validates against limits in `canSave`, so it takes *instance* limits that `ProfileView` hands it from config before editing begins. Same pattern for anything else that validates outside the view layer.
- **Version comparison uses `AppVersion.isOlder`, never string comparison** — `"1.10" < "1.9"` lexically, which would gate users out of a *newer* build. Malformed versions never gate.
- **Never use `String.hashValue` for anything persisted, rendered, or bucketed.** Swift seeds it per process, so the same input yields a different result after every launch — an unknown post tone would change color on every cold start, and a feature-flag bucket would move a user in and out of a rollout. Use `StableHash.fnv1a` (`Extensions/StableHash.swift`).
- **Picking/cropping/uploading a photo**: use `PhotoAttachmentController` (`Utilities/PhotoAttachmentController.swift`), not a fresh set of `@State` vars. `NewPostView`, `PostDetailView`'s edit mode, `ProfileView`/`ProfileDraft`'s avatar, and `OnboardingProfileStepView` all share it now — it owns pick → crop → upload state and `alertError` presentation via `PresentableAlertError`. Two per-call-site flags matter: `revertPreviewOnFailure` (does this context have a sensible previous image to fall back to?) and `alertOnFailure` (does upload failure get a modal, or does the caller show its own inline caption?) — see the type's doc comment before changing either. For the rectangular post-photo case (not the avatar's circular picker), pair it with `PhotoAttachmentTile` (`Views/Components/PhotoAttachmentTile.swift`) — a dashed empty state that morphs into the photo preview, borrowing `NewPostCard`'s "add content" visual language rather than a plain bordered button. `ImageUploader.upload` throws the real error (Supabase/network) instead of returning `nil` — don't reintroduce a `Bool`/`Optional`-returning wrapper that swallows it.
- **`LaunchHost.imageset`'s dark variant must be a true RGB invert of the light PNG, alpha unchanged** — not a "force every opaque pixel to white, keep the original alpha" derivation. The light asset (`LaunchHost.png`) is a genuine two-tone raster (opaque black outline/eye + opaque white fill + transparent background), not a single-tone silhouette with alpha-cutout face detail — forcing all opaque pixels to one color collapses the outline and eye into the same flat white as the fill, silently losing all face detail while still looking "fine" in a quick glance (this shipped once: 2026-07-29, caught only because it was compared against a true-black composite, not Xcode's neutral-gray asset-catalog preview, which hides the missing detail). Regenerate correctly with e.g. `ImageChops.invert` on the RGB channels, alpha channel untouched.
- **First-time feature callouts use TipKit** (`import TipKit`, iOS 17+ — no availability guard needed given this app's iOS 18+ minimum). `ArchiveTip.swift` (`Utilities/`) is the only one and is meant to stay rare — it's for a genuinely hard-to-discover action (Archive lives inside the "•••" menu with no other affordance), not a pattern to sprinkle on obvious UI. Shape to copy: `@Parameter static var` for a plain boolean/state gate, `static let someEvent = Event(id:)` + `.donate()` for a count-based gate (e.g. "after the Nth app launch"), combined via `#Rule` in `var rules`. `Tips.configure(...)` is called once in `On_BoardApp.init()`. A tip attached to something buried inside a `Menu` must anchor `.popoverTip()` to the menu's own trigger button, not the buried row — the row isn't rendered (and thus can't be pointed at) until the menu is already open.
- **Adding a `user_settings` column**: update `NotificationSettings.swift` **and** `SupabaseBoardService.NotificationSettingsPayload`. The payload must carry every stored column — it's a full upsert, so an omitted field silently never persists (this is exactly how `push_followed_posts` stayed dead). `NotificationSettingsPayloadTests` guards it.
- **Changing onboarding steps**: `OnboardingStatus.swift` defines the step enum; `OnboardingStore.swift` drives the state machine. `.contentPreferences` and `.graduation` are client-inserted steps with **no backing value in the `onboarding_step` Postgres enum** (`birthday`/`username`/`profile`/`school_verify`/`waitlist`/`complete` only) — `.contentPreferences`'s completion flag (`hasCompletedProfanityStep`) and its `profanityEnabled` preference are deliberately plain, un-scoped `@AppStorage` (per-device, not per-account — see `OnboardingStep.swift`'s doc comment). Don't scope these to the signed-in user; that's not a bug, it's the documented design.
- **Pledge acceptance**: `PledgeSignatureView`'s drawn signature never leaves the device (a moment of intent, not a document) — but the *fact and timestamp* of acceptance persists via `OnboardingStore.acceptPledge()` → `accept_pledge` Postgres RPC → `profiles.pledge_accepted_at` (added in `20260728165922_pledge_acceptance.sql`), fired from `WelcomeOnBoardView`'s `onSigned` callback as fire-and-forget (dismissal never waited on network before, and still doesn't). Idempotent — the RPC only sets the column `where pledge_accepted_at is null`, so a retry after a killed app can't clobber the original timestamp.
- **Changing notification logic**: update `NotificationService.swift` (iOS) and the `send-notifications` Edge Function together, and make sure any new `notify_push` trigger has a `case` in the function's `switch`. The SQL helpers `get_reengagement_targets` / `get_clearing_soon_targets` live in `supabase/migrations/20260705085734_moderation_reports_and_blocks.sql`; the follow trigger lives in `20260705141000_follow_push_notifications.sql` (later fixed by `20260705211129_…`).
- **Tests use Swift Testing** (`@Test`, `#expect`), not XCTest. All test fixtures go through mock services, not live Supabase.
- `Secrets.xcconfig` is gitignored. Never commit real keys.
- `.agents/`, `.mcp.json`, and `skills-lock.json` are Claude Code internals and are gitignored.

## TestFlight / App Store Release Checklist

Before distributing a build outside development:

1. **APNs host — nothing to do.** *(Superseded 2026-07-10.)* Earlier revisions of this file told you to redeploy with `APNS_HOST` flipped to production. **There is no `APNS_HOST` env var.** The function tries production first, falls back to sandbox on `BadDeviceToken`, and records the winner in `device_tokens.environment`. Dev, TestFlight, and App Store tokens all work unchanged.
2. **Entitlements** — `aps-environment: development` in `On Board.entitlements` is automatically overridden to `production` by Xcode's distribution provisioning profile. No manual change needed.
3. **Secrets** — confirm `Secrets.xcconfig` exists with the production `SUPABASE_ANON_KEY`. `SUPABASE_URL` is *not* read from it: `On-Board-Info.plist` hardcodes the project URL. Without the anon key the build silently ships in **mock mode** — check `AppConfiguration.isSupabaseConfigured` is `true` in the archive.
4. **Build clean** — run `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build` and confirm `** BUILD SUCCEEDED **`, then `xcodebuild test -scheme "On Board" -destination "id=<UDID>" -parallel-testing-enabled NO`.
5. **Schema** — run `supabase db pull` and confirm no unexpected drift before the release window.
6. **Edge Function triggers** — confirm every `notify_push` trigger name has a `case` in the deployed `send-notifications` switch (see Push Notifications above). A missing case fails silently.
7. **Security advisors** — run the Supabase security linter and triage anything new. Two known, accepted findings as of 2026-07-10:
   - `check_email_exists` and `check_phone_exists` are `SECURITY DEFINER` and executable by `anon`. This is **load-bearing**: `SignInView.sendOTP` calls whichever matches the active `credentialMode` *before* sign-in, both to branch sign-in vs. sign-up and to drive the "Account Found!" toast. Revoking `anon` EXECUTE on either breaks that flow for its credential type. The tradeoff is an email/phone-enumeration oracle for anyone holding the (shipped) anon key — rate-limit rather than revoke.
   - **Leaked password protection is disabled** in Supabase Auth. The app supports passwords (`SetPasswordView`), so consider enabling the HaveIBeenPwned check before a public release.
   - `rls_enabled_no_policy` on `admin_audit_log`, `admin_users`, `push_notification_ledger`, `waitlist` is intentional: RLS on with zero policies denies `anon`/`authenticated` outright; those tables are reached only through `SECURITY DEFINER` RPCs and `service_role`.
8. **Version bump** — `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.pbxproj`. App Store Connect rejects a duplicate build number.
