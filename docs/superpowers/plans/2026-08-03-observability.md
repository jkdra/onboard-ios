# Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Know that something broke, which version it broke on, and which surface — without waiting for a user to text about it. This is the *detect* half of detect → flip → fix → verify; the config and flag plans build the *flip*.

**Architecture:** A thin `ObservabilityService` protocol with a Sentry-backed implementation and a no-op mock, selected by the same `AppConfiguration.isSupabaseConfigured` / `isPreview` switch the existing service factories use — so contributor builds, previews, and tests never emit telemetry or need a DSN. Events are tagged with app version and the active flag set so a crash spike can be correlated with the rollout that caused it.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, `sentry-cocoa` (SPM).

## Global Constraints

- Minimum deployment target is iOS 18.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — never XCTest.
- **No PII in any event.** Never send handles, display names, emails, phone numbers, post or comment bodies, school domains, or avatar URLs. User association is by opaque `UUID` only.
- **No telemetry without a backend.** Contributor builds (no `Secrets.xcconfig`), previews, and the test target must use the no-op implementation. A missing DSN must never crash or warn.
- The DSN is a build secret, injected the same way as `SUPABASE_ANON_KEY`: `Secrets.xcconfig` → `On-Board-Info.plist` → `AppConfiguration`. Never commit it.
- Build check: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
- Test run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`

## Prerequisite

Tasks 2–4 of `2026-08-02-remote-config-and-flags.md` — this plan tags events with `AppVersion.current` and the resolved `FeatureFlag` set.

## Decision: Sentry over MetricKit

MetricKit is Apple-native and dependency-free, but its payloads arrive roughly once every 24 hours and you build the receiver and dashboard yourself. A 24-hour delay defeats the entire purpose here — the point is to catch a bad rollout the same day. Sentry gives crashes, non-fatals, and **release health** (crash-free session rate per app version), which is exactly the signal a staged rollout needs to be judged against. It ships its own privacy manifest.

If adding an SDK is later judged unacceptable, the `ObservabilityService` protocol in Task 1 is the seam that makes swapping it out a single-file change.

## File Structure

| File | Responsibility |
|---|---|
| `On Board/Observability/ObservabilityService.swift` | **Create.** Protocol, `NoOpObservabilityService`, factory. |
| `On Board/Observability/SentryObservabilityService.swift` | **Create.** Sentry-backed implementation and PII scrubbing. |
| `On Board/Configuration/AppConfiguration.swift` | **Modify.** Read `SentryDSN`. |
| `On-Board-Info.plist` | **Modify.** Add `SentryDSN` = `$(SENTRY_DSN)`. |
| `On Board/On_BoardApp.swift` | **Modify.** Start observability at launch; set/clear user on auth changes. |
| `On Board/Store/BoardStore+Refresh.swift` and siblings | **Modify.** Capture non-fatals at the swallowed-error paths. |
| `On BoardTests/ObservabilityTests.swift` | **Create.** Tests. |

---

### Task 1: The service seam

**Files:**
- Create: `On Board/Observability/ObservabilityService.swift`
- Test: `On BoardTests/ObservabilityTests.swift`

**Interfaces:**
- Consumes: `AppConfiguration.current`, `AppLaunchContext.isPreview`.
- Produces: `protocol ObservabilityService: Sendable` with `func start()`, `func setUser(id: UUID?)`, `func capture(_ error: Error, context: String)`, `func addBreadcrumb(_ message: String, category: String)`, `func setTag(_ value: String, for key: String)`. Plus `final class NoOpObservabilityService`, `enum ObservabilityFactory { static func make() -> any ObservabilityService }`, and `enum Observability { static let shared: any ObservabilityService }`.

- [ ] **Step 1: Write the failing test**

Create `On BoardTests/ObservabilityTests.swift`:

```swift
//
//  ObservabilityTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct ObservabilityFactoryTests {
    /// The test target has no Secrets.xcconfig, so it must get the no-op.
    /// A test run that emitted real telemetry would pollute production data
    /// and, worse, make the crash-free-sessions metric meaningless.
    @Test func unconfiguredBuildsGetTheNoOpService() {
        let service = ObservabilityFactory.make()
        #expect(service is NoOpObservabilityService)
    }

    @Test func noOpAcceptsEveryCallWithoutCrashing() {
        let service = NoOpObservabilityService()
        service.start()
        service.setUser(id: UUID())
        service.setUser(id: nil)
        service.capture(URLError(.notConnectedToInternet), context: "test")
        service.addBreadcrumb("hello", category: "test")
        service.setTag("1.1.1", for: "app_version")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/ObservabilityFactoryTests"`

Expected: FAIL to compile — `cannot find 'ObservabilityFactory' in scope`.

- [ ] **Step 3: Write the protocol, no-op, and factory**

Create `On Board/Observability/ObservabilityService.swift`:

```swift
//
//  ObservabilityService.swift
//  On Board
//
//  The seam between the app and whatever crash/error backend is in use.
//
//  Follows the same protocol + factory + mock shape as AuthService and
//  BoardService: a build with no Secrets.xcconfig (contributors, previews, the
//  test target) gets the no-op and never emits anything or needs a DSN.
//
//  NO PII EVER. Handles, display names, emails, phone numbers, post and comment
//  bodies, school domains, and avatar URLs must never reach an event. Users are
//  identified by opaque UUID only — enough to say "how many people hit this",
//  never enough to say who they are.
//

import Foundation

protocol ObservabilityService: Sendable {
    /// Called once at launch, before anything that might crash.
    func start()

    /// Associates subsequent events with a user, or clears on sign-out.
    func setUser(id: UUID?)

    /// Records a non-fatal error. `context` is a short stable identifier for the
    /// call site, e.g. "BoardStore.refresh" — not a user-facing message.
    func capture(_ error: Error, context: String)

    func addBreadcrumb(_ message: String, category: String)

    func setTag(_ value: String, for key: String)
}

final class NoOpObservabilityService: ObservabilityService {
    func start() {}
    func setUser(id: UUID?) {}
    func capture(_ error: Error, context: String) {}
    func addBreadcrumb(_ message: String, category: String) {}
    func setTag(_ value: String, for key: String) {}
}

enum ObservabilityFactory {
    static func make(
        configuration: AppConfiguration = .current,
        isPreview: Bool = AppLaunchContext.isPreview
    ) -> any ObservabilityService {
        guard !isPreview, let dsn = configuration.sentryDSN else {
            return NoOpObservabilityService()
        }
        return SentryObservabilityService(dsn: dsn)
    }
}

enum Observability {
    static let shared: any ObservabilityService = ObservabilityFactory.make()
}
```

> If `AppLaunchContext.isPreview` is spelled differently in this codebase, open
> `On Board/On_BoardApp.swift` and use the actual name — the factories there
> already branch on it.

- [ ] **Step 4: Add the DSN to configuration**

In `On Board/Configuration/AppConfiguration.swift`:

Add the stored property alongside `googleClientID`, **with an explicit memberwise
init giving it a default**:

```swift
    let sentryDSN: String?

    init(
        supabaseURL: URL?,
        supabaseAnonKey: String?,
        googleClientID: String?,
        sentryDSN: String? = nil
    ) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.googleClientID = googleClientID
        self.sentryDSN = sentryDSN
    }
```

> **This init is required, not optional.** `AppConfiguration` currently relies on
> the synthesized memberwise init, and `AppConfigurationTests` in
> `On BoardTests/On_BoardTests.swift:67` constructs it with three arguments.
> Adding a fourth stored property without a defaulted explicit init breaks every
> one of those tests at compile time.

Add it to the `load(from:)` return, reading `info["SentryDSN"] as? String` through the existing `resolveCredential` helper (which already rejects empty values and unexpanded `$(...)` placeholders):

```swift
        let sentryDSN = info["SentryDSN"] as? String
        // ...
        return AppConfiguration(
            supabaseURL: urlString.flatMap(Self.resolveURL(from:)),
            supabaseAnonKey: Self.resolveCredential(anonKey),
            googleClientID: Self.resolveCredential(googleClientID),
            sentryDSN: Self.resolveCredential(sentryDSN)
        )
```

In `On-Board-Info.plist`, add a `SentryDSN` key with value `$(SENTRY_DSN)`, matching how `SupabaseAnonKey` is declared.

> Do **not** add `SENTRY_DSN` to any committed xcconfig. It goes in the gitignored
> `Secrets.xcconfig` only. With the key absent it expands to an empty string,
> `resolveCredential` returns `nil`, and the factory hands back the no-op — the
> same silent-degradation path the Supabase factories already use.

- [ ] **Step 5: Add a temporary stub so the project compiles**

`SentryObservabilityService` doesn't exist yet. Add a placeholder in the same file so Task 1 is independently buildable; Task 2 replaces it:

```swift
// Replaced in Task 2 by the real Sentry-backed implementation.
private struct SentryObservabilityService: ObservabilityService {
    let dsn: String
    func start() {}
    func setUser(id: UUID?) {}
    func capture(_ error: Error, context: String) {}
    func addBreadcrumb(_ message: String, category: String) {}
    func setTag(_ value: String, for key: String) {}
}
```

- [ ] **Step 6: Run the tests and build**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/ObservabilityFactoryTests"`

Expected: PASS, 2 tests.

- [ ] **Step 7: Commit**

```bash
git add "On Board/Observability/ObservabilityService.swift" "On Board/Configuration/AppConfiguration.swift" "On-Board-Info.plist" "On BoardTests/ObservabilityTests.swift"
git commit -m "Add ObservabilityService seam with a no-op default"
```

---

### Task 2: The Sentry implementation

**Files:**
- Create: `On Board/Observability/SentryObservabilityService.swift`
- Modify: `On Board/Observability/ObservabilityService.swift` (remove the stub)
- Modify: `On Board.xcodeproj` (SPM dependency)

**Interfaces:**
- Consumes: the `ObservabilityService` protocol; `AppVersion.current`.
- Produces: `struct SentryObservabilityService: ObservabilityService` with `init(dsn: String)`.

- [ ] **Step 1: Add the SPM dependency**

In Xcode: File → Add Package Dependencies → `https://github.com/getsentry/sentry-cocoa` → Up to Next Major Version. Add the `Sentry` library to the **"On Board"** app target only — not the test target.

- [ ] **Step 2: Verify it resolves**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Write the implementation**

Delete the stub `SentryObservabilityService` from `ObservabilityService.swift`, then create `On Board/Observability/SentryObservabilityService.swift`:

```swift
//
//  SentryObservabilityService.swift
//  On Board
//
//  Sentry-backed observability. Only constructed when a DSN is present, which
//  means only in maintainer builds — see ObservabilityFactory.
//

import Foundation
import Sentry

struct SentryObservabilityService: ObservabilityService {
    let dsn: String

    func start() {
        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = "org.onboardapp.onboard@\(AppVersion.current)"

            // Release health: crash-free session rate per version. This is the
            // signal a staged rollout is judged against — without it a flag
            // rollout is being flown blind.
            options.enableAutoSessionTracking = true

            // Off by default: these attach request/response data and view
            // hierarchies, which is exactly where PII leaks in without anyone
            // deciding to send it.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            #if DEBUG
            options.environment = "debug"
            options.tracesSampleRate = 0.0
            #else
            options.environment = "production"
            // Low but non-zero: enough to spot a pathological regression,
            // not enough to burn the free tier's quota.
            options.tracesSampleRate = 0.05
            #endif

            // Last line of defence against PII. Anything that slips past the
            // call-site rules gets dropped here.
            options.beforeSend = { event in
                event.request = nil
                event.user?.email = nil
                event.user?.username = nil
                event.user?.ipAddress = nil
                return event
            }
        }
    }

    func setUser(id: UUID?) {
        SentrySDK.configureScope { scope in
            guard let id else {
                scope.setUser(nil)
                return
            }
            // UUID only — never a handle, email, or display name.
            scope.setUser(User(userId: id.uuidString))
        }
    }

    func capture(_ error: Error, context: String) {
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: context, key: "context")
        }
    }

    func addBreadcrumb(_ message: String, category: String) {
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    func setTag(_ value: String, for key: String) {
        SentrySDK.configureScope { $0.setTag(value: value, key: key) }
    }
}
```

- [ ] **Step 4: Start it at launch and track the user**

In `On Board/On_BoardApp.swift`, call `Observability.shared.start()` in `init()`, **before** `Tips.configure(...)` — it should be as early as possible so a crash during the rest of startup is still captured.

```swift
        Observability.shared.start()
        Observability.shared.setTag(AppVersion.current, for: "app_version")
```

Then, wherever auth state changes are already observed, associate and clear the user:

```swift
        Observability.shared.setUser(id: auth.session?.userId)
```

on sign-in, and `setUser(id: nil)` on sign-out.

- [ ] **Step 5: Tag the active flag set**

So a crash spike can be correlated with the rollout that caused it. In `RootView`, after the config refresh completes:

```swift
        for flag in FeatureFlag.allCases {
            Observability.shared.setTag(
                remoteConfig.isEnabled(flag, for: auth.session?.userId) ? "on" : "off",
                for: "flag_\(flag.rawValue)"
            )
        }
```

Without this, a rollout that causes crashes looks identical to a general regression, and there's no way to tell which flag to turn off.

- [ ] **Step 6: Update the privacy manifest**

Open `On Board/PrivacyInfo.xcprivacy`. Sentry collects crash data and (with tracing enabled) performance data. Add the corresponding `NSPrivacyCollectedDataTypes` entries — `NSPrivacyCollectedDataTypeCrashData` and `NSPrivacyCollectedDataTypePerformanceData` — each with `NSPrivacyCollectedDataTypeLinked` set to `true` (events carry a user UUID) and `NSPrivacyCollectedDataTypeTracking` set to `false`.

> Also review the App Store Connect privacy nutrition labels before submitting.
> This is a genuine change to what the app collects; declaring it wrongly is a
> review rejection and a trust problem.

- [ ] **Step 7: Verify**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`

Expected: `** BUILD SUCCEEDED **`.

Run the full suite. Expected: passes, and **no** events appear in the Sentry dashboard from the test run — the test target has no DSN and must be using the no-op.

- [ ] **Step 8: Commit**

```bash
git add "On Board/Observability/" "On Board/On_BoardApp.swift" "On Board/Views/Shared/RootView.swift" "On Board/PrivacyInfo.xcprivacy" "On Board.xcodeproj"
git commit -m "Add Sentry-backed observability with PII scrubbing and flag tagging"
```

---

### Task 3: Capture the errors currently being swallowed

**Files:**
- Modify: `On Board/Store/BoardStore+Refresh.swift`
- Modify: `On Board/Store/BoardStore+Comments.swift`, `BoardStore+Profiles.swift`, `BoardStore+Reactions.swift`
- Modify: `On Board/Configuration/RemoteConfigStore.swift`
- Modify: `On Board/Notifications/NotificationService.swift`

This is where the real value is. CLAUDE.md's read-vs-write rule means background revalidation failures are *deliberately* silent to the user — Pop Score, comments, notification settings. That is right for the user and wrong for you: those paths can fail every time for a week and nothing surfaces. Silent to the user, loud to you.

- [ ] **Step 1: Capture at the silent read paths**

Find every `catch` that logs-and-continues or is written `try?` in the background revalidation paths. At each, add:

```swift
            Observability.shared.capture(error, context: "BoardStore.refreshPopScore")
```

using a stable `context` naming the call site. Convert `try?` to `do/catch` where a capture is warranted.

Cover at minimum: `BoardStore.refresh`, `loadComments`, `refreshPopScore`, notification-settings load, `RemoteConfigStore.refresh` (replacing the `logger.debug`), and `NotificationService.upload`'s `try?` on `register_device_token` — a silently failing token upload means no pushes at all for that device, with no other symptom.

- [ ] **Step 2: Add breadcrumbs at the surfaces that have flags**

So a crash report shows what the user was doing. In `PostDetailView.onAppear`, `NewPostView.onAppear`, and `ArchiveView.onAppear`:

```swift
        Observability.shared.addBreadcrumb("opened", category: "post_detail")
```

Keep these to a handful. Breadcrumbs on every view are noise, and each is a place PII could leak — the message must be a fixed literal, never interpolated with user content.

- [ ] **Step 3: Verify no PII in any capture site**

Re-read each added call. The `context` must be a fixed literal. No `error.localizedDescription` interpolated into a tag, no post bodies, no handles.

- [ ] **Step 4: Verify and commit**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`

Expected: whole suite passes.

```bash
git add "On Board/Store" "On Board/Configuration/RemoteConfigStore.swift" "On Board/Notifications/NotificationService.swift" "On Board/Views"
git commit -m "Capture silently-swallowed background errors as non-fatals"
```

---

### Task 4: Document

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add to CLAUDE.md**

Under **Key Conventions**:

```markdown
- **Observability goes through `Observability.shared`** (`Observability/`), which
  is a no-op unless `SentryDSN` is present — so contributor builds, previews, and
  the test target never emit telemetry or need a DSN, the same way the Supabase
  factories fall back to mocks. The DSN lives in the gitignored
  `Secrets.xcconfig` as `SENTRY_DSN`; never commit it.
- **No PII in telemetry, ever.** No handles, display names, emails, phone
  numbers, post or comment bodies, school domains, or avatar URLs. Users are
  identified by opaque UUID only. `beforeSend` strips request data, email,
  username, and IP as a backstop, but the rule is enforced at the call site:
  `context` strings and breadcrumb messages must be fixed literals, never
  interpolated with user content.
- **The read-vs-write failure rule is about the *user*, not about you.** A silent
  background revalidation failure (Pop Score, comments, notification settings)
  still gets `Observability.shared.capture(_:context:)` — otherwise a path can
  fail for every user for a week with no symptom at all.
- **Events are tagged with the resolved flag set.** Without it a crash spike from
  a staged rollout is indistinguishable from a general regression, and there's no
  way to know which flag to switch off.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document observability conventions"
```

---

## Verification

- [ ] Full test suite passes and produces **zero** Sentry events.
- [ ] A maintainer build with a DSN reports a session on launch (visible in Sentry's release-health view).
- [ ] Forcing a non-fatal (e.g. airplane mode during a Pop Score refresh) produces an event with the right `context` tag and **no** PII in the payload.
- [ ] `PrivacyInfo.xcprivacy` declares crash and performance data collection.
- [ ] App Store Connect privacy labels updated before submission.
- [ ] `SENTRY_DSN` appears only in `Secrets.xcconfig` — confirm with `git grep -i "sentry.*://"` returning nothing.
