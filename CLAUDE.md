# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

On Board is a campus bulletin board iOS app built with SwiftUI + Supabase. Students join a weekly board, post anonymously, react, and comment. New boards open every Monday at midnight.

## Build & Test Commands

```bash
# Build
xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator,name=iPhone 16"

# Run all tests
xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16"

# Run a single test (uses Swift Testing, not XCTest)
xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16" -only-testing "On BoardTests/On_BoardTests/refreshMarksCompleteForSampleAppleUser"
```

No secrets are required to build. The app runs fully offline with `MockAuthService` and `MockOnboardingService` when `Secrets.xcconfig` is absent. To enable live Supabase: `cp Secrets.xcconfig.example Secrets.xcconfig` and fill in `SUPABASE_URL` / `SUPABASE_ANON_KEY`.

## Architecture Overview

### State Management
All major stores are `@Observable @MainActor` classes, injected as environment objects at the root:
- **AuthStore** — auth state machine, session management, multi-provider linking
- **BoardStore** — weekly posts, reactions, comments (in-memory, non-persistent per session)
- **OnboardingStore** — onboarding flow progression and step state
- **NetworkMonitor** — wraps `NWPathMonitor`

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

### Database
Supabase migrations live in `supabase/migrations/`. Board data is fetched via Supabase RPC functions (`fetch_active_board_week`, `fetch_posts_for_week`, `fetch_my_reactions_for_week`). Realtime subscriptions on the `reactions` table merge remote changes without overwriting the current user's local state.

## Key Conventions

- **Adding a new auth provider**: touch `AuthProvider.swift`, `AuthService.swift` protocol, `SupabaseAuthService.swift`, and `MockAuthService.swift`. Both impls must stay in sync.
- **Adding a new post/comment field**: update `Post.swift` / `Comment.swift`, `RemotePostRow.swift` (JSON decoding adapter), and the relevant Supabase RPC or table query in `SupabaseBoardService.swift`.
- **Changing onboarding steps**: `OnboardingStatus.swift` defines the step enum; `OnboardingStore.swift` drives the state machine.
- **Tests use Swift Testing** (`@Test`, `#expect`), not XCTest. All test fixtures go through mock services, not live Supabase.
- `Secrets.xcconfig` is gitignored. Never commit real keys.
