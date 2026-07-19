# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

On Board is a campus bulletin board iOS app built with SwiftUI + Supabase. Students join a weekly board, post anonymously, react, and comment. New boards open every Monday at midnight.

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

### Client-Side Cache
`BoardStore` persists a single `CacheEnvelope` (`BoardStore/CacheEnvelope.swift`) to disk via `BoardStore+DiskCache.swift`, after every successful board `apply()` and after any mutation that changes cached state (block/unblock, notification-settings save). `refresh(for:)` hydrates from this file before its `hasCachedFeed` check, so a warm cache skips the loading spinner entirely — no changes needed to `isLoading`'s existing gating.

**Adding a new cached entity**: add one field to `CacheEnvelope`, make it `Optional` (so older cache files still decode), and make sure whatever mutates it in `BoardStore` also calls `persistToDisk()`. Don't invent a second cache mechanism — one envelope, one file.

**Schema drift safety**: any decode failure (bad JSON, mismatched `CacheEnvelope.schemaVersion`) is treated as a cache miss — the file is deleted and normal network loading proceeds. Never crash on a stale/malformed cache file. Bump `schemaVersion` only when an existing field's *meaning* changes in a way old data would misrepresent — adding a new `Optional` field does not require a bump.

**Invalidation correctness**:
- Sign-out calls `clearDiskCache()` (wired into `resetForSignOut()`) — a cached board/profile/settings blob must never leak into a different account's session on the same device.
- Any mutation that changes what's cached (block, unblock, notification-settings save) calls `persistToDisk()` after resolving — don't rely solely on the next natural `refresh()` to capture it, since a force-quit in between would leave stale content cached.

**Known intentional exception — do not cache**: `ProfileView`'s live `isFollowing` check (`.task(id: profile.id)`) deliberately bypasses `followedUserIDs`/any cache and re-queries the server on every profile visit, specifically so a stale cached value can't flip "Following" back to "Follow". Don't fold this into the general cache-everything pattern.

**Read-vs-write failure rule**: background revalidation of already-cached data (Pop Score, comments, notification settings) fails silently — the user already has a value on screen. A failed *write* (a reaction, a notification-settings toggle, anything optimistic) always rolls back and surfaces an alert — never fail a save silently.

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

**Migration history (verified 2026-07-10):** local `supabase/migrations/` matches the remote ledger exactly — 17 migrations, oldest `20260703000000_storage_cleanup`. The 2026-06-29 reconciliation baselines (`20260629081312_remote_schema`, `20260629120000_device_tokens_rls_initplan`) are **no longer in the remote ledger**; don't expect to find them. Pre-reconciliation files are preserved under `supabase/migrations/_archive_drift_2026-06-29/` — do not resurrect them. `supabase db pull` / `db push` work normally; add new changes as fresh timestamped migrations and push through a preview branch. Avoid hand-editing the remote migration ledger.

### UI Conventions
- **In-flight buttons** use `LoadingButtonLabel(_:systemImage:isLoading:)` (a spinner to the left of the title), paired with `.disabled(isLoading)` on the page — never swap the screen for a separate loading view. Spinner tint defaults to `systemBackground` (matches `.boardPrimary`); pass `spinnerTint: .accentColor`/`.primary` for non-filled buttons.
- **Keyboard dismissal:** attach `.keyboardDoneToolbar()` (adds a "Done" key accessory) and `.scrollDismissesKeyboard(.interactively)` to any screen hosting text input. Both route through `KeyboardDismisser.dismiss()` (see `Extensions/View+KeyboardDismiss.swift`), which resigns first responder app-wide — no per-field `@FocusState` plumbing needed.
- **Composed tap gestures:** a double-tap that coexists with drag/magnification gestures must use `SpatialTapGesture(count: 2)` (location + count in one recognizer) or a `.simultaneousGesture(TapGesture(count: 2))` — a plain `.onTapGesture(count: 2)` loses gesture arbitration and silently never fires.
- **Gesture priority near system controls:** a plain `.gesture()` layered over a `TextField`/other UIKit-bridged control loses arbitration to that control's own recognizers — a swipe/drag starting on the control itself (not just its padding) silently never fires. Use `.highPriorityGesture()` instead; it only claims the touch once its own recognition threshold (e.g. `minimumDistance`) is cleared, so taps/typing/cursor placement pass through untouched. See `CommentComposerBar.fieldCluster`'s swipe-to-expand.
- **Deferred gesture resolution after navigation:** single/double-tap disambiguation (`ExclusiveGesture` + `SpatialTapGesture(count:)`) carries the system's standard delay, and the zoom navigation transition below keeps a popped destination mounted through the pop animation — so a tap made right before backing out can resolve *after* the view is gone, acting on stale state (e.g. silently reopening a `fullScreenCover` on a screen the user already left). `DoubleTapHeart.swift` guards this with an `isPresentedOnScreen` flag (`true` on `.onAppear`, `false` on `.onDisappear`) checked before the gesture's effect runs. Any new tap-disambiguating or otherwise-deferred gesture handler on a pushed screen needs the same guard.
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
- **Adding a `user_settings` column**: update `NotificationSettings.swift` **and** `SupabaseBoardService.NotificationSettingsPayload`. The payload must carry every stored column — it's a full upsert, so an omitted field silently never persists (this is exactly how `push_followed_posts` stayed dead). `NotificationSettingsPayloadTests` guards it.
- **Changing onboarding steps**: `OnboardingStatus.swift` defines the step enum; `OnboardingStore.swift` drives the state machine.
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
   - `check_email_exists` is `SECURITY DEFINER` and executable by `anon`. This is **load-bearing**: `SupabaseAuthService.checkEmailExists` calls it *before* sign-in to branch sign-in vs. sign-up. Revoking `anon` EXECUTE breaks email sign-in. The tradeoff is an email-enumeration oracle for anyone holding the (shipped) anon key — rate-limit it rather than revoke it.
   - **Leaked password protection is disabled** in Supabase Auth. The app supports passwords (`SetPasswordView`), so consider enabling the HaveIBeenPwned check before a public release.
   - `rls_enabled_no_policy` on `admin_audit_log`, `admin_users`, `push_notification_ledger`, `waitlist` is intentional: RLS on with zero policies denies `anon`/`authenticated` outright; those tables are reached only through `SECURITY DEFINER` RPCs and `service_role`.
8. **Version bump** — `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.pbxproj`. App Store Connect rejects a duplicate build number.
