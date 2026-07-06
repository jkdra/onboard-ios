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

No secrets are required to build. The app runs fully offline with `MockAuthService` and `MockOnboardingService` when `Secrets.xcconfig` is absent. To enable live Supabase: `cp Secrets.xcconfig.example Secrets.xcconfig` and fill in `SUPABASE_URL` / `SUPABASE_ANON_KEY`.

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

The entry point (`On_BoardApp.swift`) selects mock vs. live using `AppLaunchContext.isPreview`.

### Optimistic Updates
`BoardStore+Interactions.swift` applies all mutations (reactions, post creation, comments) locally first, then syncs to Supabase. On error it rolls back and surfaces the error. Never skip the rollback path when adding new mutations.

### Navigation Flow
```
RootView
  ├── auth.isSignedIn == false  →  SignInView
  └── auth.isSignedIn == true
        ├── onboarding.needsOnboarding  →  OnboardingCoordinator
        └── otherwise                   →  ContentView (Feed)
```

### Configuration
`AppConfiguration.swift` reads `SupabaseURL`, `SupabaseAnonKey`, and optionally `GoogleClientID` from `Info.plist` (populated by `Secrets.xcconfig` at build time). If either Supabase key is missing/placeholder, `AppConfiguration.isConfigured` returns `false` and the app runs in mock mode.

### Deep Linking
Post sharing supports both a universal link (`https://onboardapp.org/post/<UUID>`, requires the `com.apple.developer.associated-domains` entitlement pointing at `applinks:onboardapp.org`) and a custom scheme fallback (`onboard://post/<UUID>`). Both are parsed in `On_BoardApp.swift`'s `onOpenURL`, which hands the post ID to `NotificationService.shared.setPendingPostID(_:)` — the same pending-post mechanism used by push notification taps. OAuth callback URLs and magic-link URLs pass through the same `onOpenURL` but are routed to Supabase's `client.auth.handle(url)` instead. Because magic-link/external sign-ins resolve silently in the SDK, `On_BoardApp.swift` also observes `client.auth.authStateChanges` and calls `auth.restoreSession()` on a `.signedIn` event the app didn't initiate interactively.

### Database
Supabase migrations live in `supabase/migrations/`. Board data is fetched via Supabase RPC functions (`fetch_active_board_week`, `fetch_posts_for_week`, `fetch_my_reactions_for_week`). There is no realtime subscription for reactions/posts — the board is weekly-cadence, not live chat, so a Supabase Realtime channel wasn't worth its always-on connection and scaling cost (it had no server-side filter, meaning every reaction on every board streamed to every client). Freshness instead comes from pull-to-refresh, a foreground-triggered refresh (`RootView`'s `scenePhase` handler), and a silent ~45s poll in `ContentView` while the feed is on screen. `BoardStore.refresh(for:)` coalesces concurrent calls, so polling it repeatedly is cheap.

**Migration history (reconciled 2026-06-29):** the folder was collapsed to a single live-matching baseline, `20260629081312_remote_schema.sql`, after a period of ledger drift. The pre-reconciliation files are preserved under `supabase/migrations/_archive_drift_2026-06-29/` (including the old `README_DRIFT` notes) — do not resurrect them. The local folder now matches the remote ledger, so `supabase db pull` and `supabase db push` work normally again; add new changes as fresh timestamped migrations and push through a preview branch. Both baseline migrations (`20260629081312_remote_schema` and `20260629120000_device_tokens_rls_initplan`) are applied remotely. Avoid hand-editing the remote migration ledger.

### UI Conventions
- **In-flight buttons** use `LoadingButtonLabel(_:systemImage:isLoading:)` (a spinner to the left of the title), paired with `.disabled(isLoading)` on the page — never swap the screen for a separate loading view. Spinner tint defaults to `systemBackground` (matches `.boardPrimary`); pass `spinnerTint: .accentColor`/`.primary` for non-filled buttons.
- **Keyboard dismissal:** attach `.keyboardDoneToolbar()` (adds a "Done" key accessory) and `.scrollDismissesKeyboard(.interactively)` to any screen hosting text input. Both route through `KeyboardDismisser.dismiss()` (see `Extensions/View+KeyboardDismiss.swift`), which resigns first responder app-wide — no per-field `@FocusState` plumbing needed.
- **Composed tap gestures:** a double-tap that coexists with drag/magnification gestures must use `SpatialTapGesture(count: 2)` (location + count in one recognizer) or a `.simultaneousGesture(TapGesture(count: 2))` — a plain `.onTapGesture(count: 2)` loses gesture arbitration and silently never fires.
- **Auth → onboarding transition:** a fresh interactive sign-in keeps `SignInView` in place (form disabled, tapped button spinning) until status resolves; only a silent cold-launch `restoreSession` shows the covering loader (`OnboardingCoordinator.interactiveSignIn` gates this — interactive sign-ins pass through `.signingIn`, restore does not).
- **Onboarding progress bar:** `OnboardingProgressBar` (replaced the old `OnboardingProgressBackground`) animates via a shared `Namespace` injected through `EnvironmentValues.onboardingNamespace` (set once in `OnboardingCoordinator`) and a `matchedGeometryEffect`, not a per-step `.overlay` positioned by `path.count`. Any new step view needs no special wiring — it inherits the environment namespace automatically.

### Push Notifications
Push is delivered via APNs using a `.p8` key stored as a Supabase Edge Function secret. The `send-notifications` Edge Function handles four triggers fired by `pg_cron` jobs:

| Trigger | Schedule (UTC) | Audience |
|---|---|---|
| `monday-reset` | Mon 14:30 | Everyone |
| `re-engagement` | Mon–Sat 17:00 | Inactive 2+ days with unseen posts |
| `sunday-reengagement` | Sun 19:00 | Anyone with unseen posts |
| `clearing-soon` | Mon 03:00 | Everyone (body varies by unseen post count) |

The Edge Function uses `api.sandbox.push.apple.com` — change to `api.push.apple.com` before App Store submission.

## Key Conventions

- **Adding a new auth provider**: touch `AuthProvider.swift`, `AuthService.swift` protocol, `SupabaseAuthService.swift`, and `MockAuthService.swift`. Both impls must stay in sync.
- **Unlinking or deleting an account with a linked Apple/Google identity**: revoke the provider token first, then unlink/delete — don't skip this, Apple/Google otherwise still consider the app authorized. Apple requires an authorization code (obtained via a fresh `AppleSignInCoordinator.requestAuthorization()` + `authorizationCode(from:)`) passed to `AuthStore.revokeApple(authorizationCode:)`, which calls the `revoke-apple` Supabase Edge Function. Google is simpler — `GoogleSignInService.disconnect()` is called locally (no server round-trip) from `SupabaseAuthService`'s unlink/sign-out paths. Both `AccountSecuritySettingsView` (unlink) and `DeleteAccountView` (delete) call the Apple revoke step before their respective `AuthStore` call.
- **Adding a new post/comment field**: update `Post.swift` / `Comment.swift`, `RemotePostRow.swift` (JSON decoding adapter), and the relevant Supabase RPC or table query in `SupabaseBoardService.swift`.
- **Changing onboarding steps**: `OnboardingStatus.swift` defines the step enum; `OnboardingStore.swift` drives the state machine.
- **Changing notification logic**: update `NotificationService.swift` (iOS) and the `send-notifications` Edge Function together. The SQL helper functions `get_reengagement_targets` and `get_clearing_soon_targets` live in `supabase/migrations/20260624000000_push_notifications.sql`.
- **Tests use Swift Testing** (`@Test`, `#expect`), not XCTest. All test fixtures go through mock services, not live Supabase.
- `Secrets.xcconfig` is gitignored. Never commit real keys.
- `.agents/`, `.mcp.json`, and `skills-lock.json` are Claude Code internals and are gitignored.

## TestFlight / App Store Release Checklist

Before distributing a build outside development:

1. **APNs host** — redeploy `send-notifications` edge function with `APNS_HOST` changed from `https://api.sandbox.push.apple.com` to `https://api.push.apple.com`. Sandbox tokens are rejected by production APNs; push notifications will silently fail without this change.
2. **Entitlements** — `aps-environment: development` in `On Board.entitlements` is automatically overridden to `production` by Xcode's distribution provisioning profile. No manual change needed.
3. **Secrets** — confirm `Secrets.xcconfig` has production `SUPABASE_URL` and `SUPABASE_ANON_KEY` (already the case; the URL is also hardcoded in `Info.plist` as a fallback).
4. **Build clean** — run `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build` and confirm `** BUILD SUCCEEDED **` with no errors.
5. **Schema** — run `supabase db pull` and confirm no unexpected drift before the release window.
