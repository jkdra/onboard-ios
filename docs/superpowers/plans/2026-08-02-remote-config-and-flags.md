# Remote Config, Feature Flags & Version Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let values, feature availability, and a minimum-version requirement be changed server-side without shipping a build — so a finished feature can ship inert and be switched on when we choose, and a broken surface can be switched off in minutes.

**Architecture:** A `SECURITY DEFINER` Postgres RPC returns an allowlisted `jsonb` blob of string key/value pairs. A `RemoteConfigStore` (`@Observable @MainActor`, injected at the root) fetches it fire-and-forget at launch and on foreground, caches it in `UserDefaults`, and exposes it as a `RemoteConfig` value whose every accessor falls back to the currently-compiled default. Feature flags are the same mechanism with `flag_`-prefixed keys and per-user percentage bucketing via `StableHash`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, supabase-swift, Postgres (Supabase).

## Global Constraints

- Minimum deployment target is iOS 18. iOS 26 APIs require `#available(iOS 26.0, *)` guards.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — never XCTest.
- **Never write snake_case `CodingKeys`** on a type crossing PostgREST. `BoardJSON` applies `.convertToSnakeCase`/`.convertFromSnakeCase`; explicit snake_case keys make encoding work while decoding always throws `keyNotFound`.
- **Never use `String.hashValue`** for bucketing — it's seeded per process, so a user would move in and out of a rollout on every launch. Use `StableHash.fnv1a` from the forward-compatible-decoding plan.
- **The default value is always current shipped behavior.** A server returning `{}` must be indistinguishable from today's build. No accessor may cause a caller to skip behavior it does today.
- Config fetch is **fire-and-forget** and must never block first render or gate the sign-in path.
- Migrations: apply via the Supabase MCP `apply_migration`, which stamps its own remote version — rename the local SQL file to match afterward.
- Build check: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
- Test run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`

## Prerequisite

Task 1 of `2026-08-01-forward-compatible-decoding.md` must be complete — this plan uses `StableHash.fnv1a`.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/<ts>_app_config_rpc.sql` | **Create.** `get_app_config()` RPC + grants. |
| `supabase/migrations/<ts>_device_token_app_version.sql` | **Create.** `device_tokens.app_version` + updated `register_device_token`. |
| `On Board/Configuration/RemoteConfig.swift` | **Create.** The value type and every typed accessor. The only file containing config key strings. |
| `On Board/Configuration/FeatureFlag.swift` | **Create.** Flag enum, compiled defaults, bucketing. |
| `On Board/Configuration/RemoteConfigStore.swift` | **Create.** Fetch, `UserDefaults` persistence, install identity. |
| `On Board/Views/Shared/UpdateAvailableModifier.swift` | **Create.** Soft and blocking update prompts. |
| `On Board/Views/Shared/RootView.swift` | **Modify.** Launch + foreground fetch; attach the update modifier. |
| `On Board/On_BoardApp.swift` | **Modify.** Instantiate and inject `RemoteConfigStore`. |
| `On Board/Notifications/NotificationService.swift:120` | **Modify.** Send app version with the device token. |
| Various call sites | **Modify.** Task 6 routes eight compiled constants through config. |
| `On BoardTests/RemoteConfigTests.swift` | **Create.** All tests for this plan. |

---

### Task 1: The `get_app_config` RPC

**Files:**
- Create: `supabase/migrations/<timestamp>_app_config_rpc.sql`

**Interfaces:**
- Consumes: the existing `public.app_config` table (`key text, value text, updated_at`).
- Produces: `public.get_app_config() returns jsonb`, executable by `anon` and `authenticated`.

- [ ] **Step 1: Write the migration**

Create the file with:

```sql
-- Client-readable subset of app_config, returned as one jsonb blob.
--
-- SECURITY DEFINER + an explicit key allowlist rather than a table policy:
-- app_config also holds server-only keys (board_timezone drives the cron reset),
-- and `select *` would hand every one of them to anyone holding the shipped anon
-- key. Adding a client-facing key is therefore a reviewed migration, which costs
-- nothing — a new key already needs a client build for its typed accessor.
--
-- 'flag_%' is deliberately open-ended: feature flags are booleans or percentages
-- and carry no secrets by construction, so a new flag needs no migration.
create or replace function public.get_app_config()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.app_config
  where key like 'flag\_%' or key in (
    'min_supported_version',
    'recommended_version',
    'feed_poll_seconds',
    'otp_cooldown_seconds',
    'referral_one_month_threshold',
    'referral_three_month_threshold',
    'referral_disclosure_threshold',
    'board_clearing_soon_hours',
    'board_final_hour_lockout_hours',
    'handle_change_window_days',
    'handle_change_max_per_window',
    'comment_max_length',
    'bio_max_length',
    'display_name_max_length',
    'max_cached_archive_weeks',
    'referral_share_message',
    'referral_share_message_instant'
  );
$$;

revoke all on function public.get_app_config() from public;
-- anon, not just authenticated: the version gate and any auth-flow flag must be
-- readable before sign-in, which is exactly when a broken sign-in needs them.
-- Same precedent as check_email_exists.
grant execute on function public.get_app_config() to anon, authenticated;
```

- [ ] **Step 2: Apply the migration**

Apply via the Supabase MCP `apply_migration` tool with name `app_config_rpc`. Then rename the local file to match the remote version stamp it returns.

- [ ] **Step 3: Verify it returns an empty object and leaks nothing**

Run via the Supabase MCP `execute_sql`:

```sql
select public.get_app_config();
```

Expected: `{}` — `board_timezone` is the only row in `app_config` and it is **not** in the allowlist. If `board_timezone` appears in the output, the allowlist is wrong; fix before continuing.

- [ ] **Step 4: Verify an allowlisted key does come through**

```sql
insert into public.app_config (key, value) values ('feed_poll_seconds', '45')
  on conflict (key) do update set value = excluded.value;
select public.get_app_config();
delete from public.app_config where key = 'feed_poll_seconds';
```

Expected: the middle statement returns `{"feed_poll_seconds": "45"}`. The delete restores the empty state — **1.1.1 must ship with no keys seeded**.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/
git commit -m "Add get_app_config RPC returning an allowlisted client config blob"
```

> `supabase/` is gitignored in this repo by design. If `git add` reports nothing to add, that is expected — record the migration in the sibling `../supabase/` checkout instead.

---

### Task 2: The `RemoteConfig` value type

**Files:**
- Create: `On Board/Configuration/RemoteConfig.swift`
- Test: `On BoardTests/RemoteConfigTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `RemoteConfig` (`Sendable`, `Equatable`) with `init(values: [String: String])`, `static let empty`, and typed accessors: `feedPollSeconds: TimeInterval`, `otpCooldownSeconds: Int`, `referralOneMonthThreshold: Int`, `referralThreeMonthThreshold: Int`, `referralDisclosureThreshold: Int`, `boardClearingSoonHours: Int`, `boardFinalHourLockoutHours: Int`, `handleChangeWindowDays: Int`, `handleChangeMaxPerWindow: Int`, `commentMaxLength: Int`, `bioMaxLength: Int`, `displayNameMaxLength: Int`, `maxCachedArchiveWeeks: Int`, `referralShareMessage: String?`, `referralShareMessageInstant: String?`, `minSupportedVersion: String?`, `recommendedVersion: String?`, and `rawValue(for: String) -> String?`.

- [ ] **Step 1: Write the failing test**

Create `On BoardTests/RemoteConfigTests.swift`:

```swift
//
//  RemoteConfigTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct RemoteConfigDefaultsTests {
    @Test func emptyConfigReturnsCompiledDefaults() {
        let config = RemoteConfig.empty
        #expect(config.feedPollSeconds == 45)
        #expect(config.otpCooldownSeconds == 60)
        #expect(config.referralOneMonthThreshold == 4)
        #expect(config.referralThreeMonthThreshold == 5)
        #expect(config.referralDisclosureThreshold == 3)
        #expect(config.boardClearingSoonHours == 3)
        #expect(config.boardFinalHourLockoutHours == 1)
        #expect(config.handleChangeWindowDays == 14)
        #expect(config.handleChangeMaxPerWindow == 2)
        #expect(config.commentMaxLength == 280)
        #expect(config.bioMaxLength == 300)
        #expect(config.displayNameMaxLength == 50)
        #expect(config.maxCachedArchiveWeeks == 3)
        #expect(config.referralShareMessage == nil)
        #expect(config.minSupportedVersion == nil)
    }

    @Test func serverValuesOverrideDefaults() {
        let config = RemoteConfig(values: ["feed_poll_seconds": "120", "comment_max_length": "500"])
        #expect(config.feedPollSeconds == 120)
        #expect(config.commentMaxLength == 500)
        // Untouched keys keep their compiled defaults.
        #expect(config.otpCooldownSeconds == 60)
    }

    @Test func unparseableValuesFallBackInsteadOfCrashing() {
        let config = RemoteConfig(values: ["feed_poll_seconds": "soon", "comment_max_length": ""])
        #expect(config.feedPollSeconds == 45)
        #expect(config.commentMaxLength == 280)
    }

    @Test func unknownKeysAreIgnored() {
        let config = RemoteConfig(values: ["some_future_key": "1", "feed_poll_seconds": "90"])
        #expect(config.feedPollSeconds == 90)
    }

    @Test func decodesFromTheRPCShape() throws {
        let json = Data(#"{"feed_poll_seconds":"90","flag_zoomTransition":"off"}"#.utf8)
        let values = try JSONDecoder().decode([String: String].self, from: json)
        let config = RemoteConfig(values: values)
        #expect(config.feedPollSeconds == 90)
        #expect(config.rawValue(for: "flag_zoomTransition") == "off")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/RemoteConfigDefaultsTests"`

Expected: FAIL to compile — `cannot find 'RemoteConfig' in scope`.

- [ ] **Step 3: Write the type**

Create `On Board/Configuration/RemoteConfig.swift`:

```swift
//
//  RemoteConfig.swift
//  On Board
//
//  Server-supplied values that parameterize shipped native behavior.
//
//  THE DEFAULT IS ALWAYS CURRENT SHIPPED BEHAVIOR. Every accessor falls back to
//  the value that was compiled in, so a server returning `{}` — or a failed
//  fetch, or an unparseable value — is byte-for-byte indistinguishable from a
//  build with no remote config at all. Never add an accessor whose fallback
//  causes the caller to skip behavior it does today.
//
//  The wire shape is an untyped string map on purpose: unknown keys are ignored
//  (so a newer server can't break an older client) and missing keys fall back
//  (so an older server can't break a newer client). Call sites never see a
//  string — this is the only file in the app that contains config key literals.
//

import Foundation

struct RemoteConfig: Sendable, Equatable {
    private let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    static let empty = RemoteConfig(values: [:])

    // MARK: - Timing

    var feedPollSeconds: TimeInterval { double("feed_poll_seconds") ?? 45 }
    var otpCooldownSeconds: Int { int("otp_cooldown_seconds") ?? 60 }

    // MARK: - Referral ladder

    var referralOneMonthThreshold: Int { int("referral_one_month_threshold") ?? 4 }
    var referralThreeMonthThreshold: Int { int("referral_three_month_threshold") ?? 5 }
    var referralDisclosureThreshold: Int { int("referral_disclosure_threshold") ?? 3 }
    var referralShareMessage: String? { values["referral_share_message"] }
    var referralShareMessageInstant: String? { values["referral_share_message_instant"] }

    // MARK: - Board schedule
    //
    // These mirror server-side rules. The server stays authoritative — a stale
    // client shows a slightly wrong countdown, it never lets a write succeed
    // that the server would reject.

    var boardClearingSoonHours: Int { int("board_clearing_soon_hours") ?? 3 }
    var boardFinalHourLockoutHours: Int { int("board_final_hour_lockout_hours") ?? 1 }

    // MARK: - Account rules (mirrors of server rules)

    var handleChangeWindowDays: Int { int("handle_change_window_days") ?? 14 }
    var handleChangeMaxPerWindow: Int { int("handle_change_max_per_window") ?? 2 }

    // MARK: - Field limits
    //
    // Display hints only. If the server also enforces a limit, it is the
    // authority; a client value larger than the server's produces a confusing
    // rejection, so raise the server first.

    var commentMaxLength: Int { int("comment_max_length") ?? 280 }
    var bioMaxLength: Int { int("bio_max_length") ?? 300 }
    var displayNameMaxLength: Int { int("display_name_max_length") ?? 50 }

    // MARK: - Cache

    var maxCachedArchiveWeeks: Int { int("max_cached_archive_weeks") ?? 3 }

    // MARK: - Version gate

    var minSupportedVersion: String? { values["min_supported_version"] }
    var recommendedVersion: String? { values["recommended_version"] }

    // MARK: - Raw access (feature flags only)

    /// Feature flags are read through `FeatureFlag`, which needs the raw string.
    /// Nothing else should use this — add a typed accessor instead.
    func rawValue(for key: String) -> String? { values[key] }

    // MARK: - Parsing

    private func int(_ key: String) -> Int? {
        guard let raw = values[key], let value = Int(raw) else { return nil }
        return value
    }

    private func double(_ key: String) -> Double? {
        guard let raw = values[key], let value = Double(raw) else { return nil }
        return value
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/RemoteConfigDefaultsTests"`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add "On Board/Configuration/RemoteConfig.swift" "On BoardTests/RemoteConfigTests.swift"
git commit -m "Add RemoteConfig with compiled-default fallbacks for every value"
```

---

### Task 3: Feature flags with percentage bucketing

**Files:**
- Create: `On Board/Configuration/FeatureFlag.swift`
- Test: `On BoardTests/RemoteConfigTests.swift`

**Interfaces:**
- Consumes: `RemoteConfig.rawValue(for:)`, `StableHash.fnv1a`.
- Produces: `enum FeatureFlag: String, CaseIterable` with cases `zoomTransition`, `glassEffects`, `postPhotoAttachments`, `hostVoice`; `var compiledDefault: Bool`; `RemoteConfig.isEnabled(_ flag: FeatureFlag, for identity: UUID) -> Bool`.

- [ ] **Step 1: Write the failing test**

Append to `On BoardTests/RemoteConfigTests.swift`:

```swift
struct FeatureFlagTests {
    private let identity = UUID(uuidString: "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E01")!

    @Test func absentFlagUsesCompiledDefault() {
        let config = RemoteConfig.empty
        // Every existing surface ships enabled, so its default must be true —
        // otherwise 1.1.1 would silently turn features off.
        for flag in FeatureFlag.allCases {
            #expect(config.isEnabled(flag, for: identity) == flag.compiledDefault)
        }
    }

    @Test func everyExistingSurfaceDefaultsOn() {
        for flag in FeatureFlag.allCases {
            #expect(flag.compiledDefault)
        }
    }

    @Test func explicitOnAndOffWin() {
        let on = RemoteConfig(values: ["flag_zoomTransition": "on"])
        let off = RemoteConfig(values: ["flag_zoomTransition": "off"])
        #expect(on.isEnabled(.zoomTransition, for: identity))
        #expect(!off.isEnabled(.zoomTransition, for: identity))
    }

    @Test func zeroPercentIsOffForEveryoneAndHundredIsOnForEveryone() {
        let none = RemoteConfig(values: ["flag_zoomTransition": "0"])
        let all = RemoteConfig(values: ["flag_zoomTransition": "100"])
        for _ in 0..<200 {
            let id = UUID()
            #expect(!none.isEnabled(.zoomTransition, for: id))
            #expect(all.isEnabled(.zoomTransition, for: id))
        }
    }

    @Test func bucketingIsStableForTheSameIdentity() {
        let config = RemoteConfig(values: ["flag_zoomTransition": "50"])
        let first = config.isEnabled(.zoomTransition, for: identity)
        for _ in 0..<50 {
            #expect(config.isEnabled(.zoomTransition, for: identity) == first)
        }
    }

    @Test func aPartialRolloutSelectsRoughlyThatShare() {
        let config = RemoteConfig(values: ["flag_zoomTransition": "50"])
        let ids = (0..<1000).map { _ in UUID() }
        let enabled = ids.filter { config.isEnabled(.zoomTransition, for: $0) }.count
        // Wide band — this pins "it actually samples", not statistical precision.
        #expect(enabled > 350 && enabled < 650)
    }

    /// The salt is what stops the same unlucky cohort from receiving every
    /// staged rollout forever. Without it, two flags at 10% select identical users.
    @Test func differentFlagsAtTheSamePercentageSelectDifferentCohorts() {
        let config = RemoteConfig(values: [
            "flag_zoomTransition": "50",
            "flag_glassEffects": "50"
        ])
        let ids = (0..<500).map { _ in UUID() }
        let a = Set(ids.filter { config.isEnabled(.zoomTransition, for: $0) })
        let b = Set(ids.filter { config.isEnabled(.glassEffects, for: $0) })
        #expect(a != b)
    }

    @Test func unparseableValueFallsBackToCompiledDefault() {
        let config = RemoteConfig(values: ["flag_zoomTransition": "maybe"])
        #expect(config.isEnabled(.zoomTransition, for: identity) == FeatureFlag.zoomTransition.compiledDefault)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/FeatureFlagTests"`

Expected: FAIL to compile — `cannot find 'FeatureFlag' in scope`.

- [ ] **Step 3: Write the flag type**

Create `On Board/Configuration/FeatureFlag.swift`:

```swift
//
//  FeatureFlag.swift
//  On Board
//
//  Server-controlled switches for shipped native surfaces.
//
//  Every new feature should be born here, defaulted `false`, and merged and
//  shipped inert. That is what decouples "the feature is finished" from "Apple
//  approved the build" — the code reaches devices on the normal release cadence
//  and is switched on whenever we choose.
//
//  Existing surfaces added retroactively default `true`, because their compiled
//  default must equal what the app already does.
//

import Foundation

enum FeatureFlag: String, CaseIterable, Sendable {
    /// The feed-card → post-detail zoom navigation transition. CLAUDE.md
    /// documents four separate landmine categories around it, and the fallback
    /// (a plain push) is trivially correct — the highest-value switch in the app.
    case zoomTransition

    /// iOS 26 `glassEffect` styling. The non-glass path already ships to iOS 18
    /// users, so the fallback is proven code rather than a dormant branch.
    case glassEffects

    /// Photo attachments on posts. Lets an upload or moderation incident degrade
    /// to text-only posting instead of taking the whole app down.
    case postPhotoAttachments

    /// The Host's Animalese speech synthesis. Audio work on a hot path is a
    /// plausible performance surface; muting is cheap.
    case hostVoice

    /// Behavior when the server says nothing — must equal what the app does today.
    var compiledDefault: Bool {
        switch self {
        case .zoomTransition, .glassEffects, .postPhotoAttachments, .hostVoice:
            true
        }
    }

    var configKey: String { "flag_\(rawValue)" }
}

extension RemoteConfig {
    /// Resolves a flag for one identity.
    ///
    /// Values are `on`, `off`, or an integer 0–100 for a staged rollout.
    /// Anything else falls back to the compiled default.
    func isEnabled(_ flag: FeatureFlag, for identity: UUID) -> Bool {
        switch rawValue(for: flag.configKey) {
        case "on":
            return true
        case "off":
            return false
        case .some(let raw):
            guard let percentage = Int(raw), (0...100).contains(percentage) else {
                return flag.compiledDefault
            }
            return Self.bucket(identity, salt: flag.rawValue) < percentage
        case nil:
            return flag.compiledDefault
        }
    }

    /// Stable 0–99 bucket for an identity within one flag.
    ///
    /// Salted with the flag name on purpose: bucketing on identity alone would
    /// put the same unlucky ~10% of users into *every* staged rollout forever,
    /// turning a sampling strategy into one permanently experimented-on cohort.
    ///
    /// Uses `StableHash`, never `hashValue` — Swift seeds that per process, so a
    /// user would move in and out of the rollout on every cold launch.
    static func bucket(_ identity: UUID, salt: String) -> Int {
        Int(StableHash.fnv1a("\(identity.uuidString):\(salt)") % 100)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/FeatureFlagTests"`

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add "On Board/Configuration/FeatureFlag.swift" "On BoardTests/RemoteConfigTests.swift"
git commit -m "Add feature flags with salted per-user percentage bucketing"
```

---

### Task 4: `RemoteConfigStore` — fetch, cache, install identity

**Files:**
- Create: `On Board/Configuration/RemoteConfigStore.swift`
- Modify: `On Board/On_BoardApp.swift`
- Modify: `On Board/Views/Shared/RootView.swift:109-114`
- Test: `On BoardTests/RemoteConfigTests.swift`

**Interfaces:**
- Consumes: `RemoteConfig`, `FeatureFlag`, `SupabaseClientFactory.client(for:)`.
- Produces: `@Observable @MainActor final class RemoteConfigStore` with `var config: RemoteConfig`, `var installIdentity: UUID`, `func refresh() async`, `func isEnabled(_ flag: FeatureFlag, for userID: UUID?) -> Bool`, and `init(defaults: UserDefaults = .standard)`.

**Why `UserDefaults` and not `CacheEnvelope`:** `CacheEnvelope` is deleted by `clearDiskCache()` on sign-out and is hydrated asynchronously off-main by `BoardStore`. Config must survive sign-out (it is app configuration, not account data) and must be readable **synchronously, before sign-in** — the version gate and any auth-flow flag are needed exactly when a user is signed out. The payload is ~20 short strings, so it needs no async hydration. CLAUDE.md's "one envelope, one file" rule governs cached board *entities*; this is a deliberate, documented exception.

- [ ] **Step 1: Write the failing test**

Append to `On BoardTests/RemoteConfigTests.swift`:

```swift
@MainActor
struct RemoteConfigStoreTests {
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsEmptyWithNoStoredConfig() {
        let store = RemoteConfigStore(defaults: isolatedDefaults("test.empty"))
        #expect(store.config == .empty)
        #expect(store.config.feedPollSeconds == 45)
    }

    @Test func restoresStoredConfigOnInit() {
        let name = "test.restore"
        let defaults = isolatedDefaults(name)
        let first = RemoteConfigStore(defaults: defaults)
        first.apply(["feed_poll_seconds": "120"])

        let second = RemoteConfigStore(defaults: defaults)
        #expect(second.config.feedPollSeconds == 120)
    }

    @Test func installIdentityIsStableAcrossInstances() {
        let name = "test.identity"
        let defaults = isolatedDefaults(name)
        let first = RemoteConfigStore(defaults: defaults).installIdentity
        let second = RemoteConfigStore(defaults: defaults).installIdentity
        #expect(first == second)
    }

    @Test func flagsResolveAgainstUserIDWhenSignedInAndInstallIdentityWhenNot() {
        let store = RemoteConfigStore(defaults: isolatedDefaults("test.flags"))
        store.apply(["flag_zoomTransition": "100"])
        #expect(store.isEnabled(.zoomTransition, for: UUID()))
        #expect(store.isEnabled(.zoomTransition, for: nil))
    }

    @Test func applyingIdenticalValuesDoesNotRewriteStorage() {
        let name = "test.nowrite"
        let defaults = isolatedDefaults(name)
        let store = RemoteConfigStore(defaults: defaults)
        store.apply(["feed_poll_seconds": "120"])
        let firstWrite = defaults.object(forKey: RemoteConfigStore.storageKey) as? [String: String]
        store.apply(["feed_poll_seconds": "120"])
        let secondWrite = defaults.object(forKey: RemoteConfigStore.storageKey) as? [String: String]
        #expect(firstWrite == secondWrite)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/RemoteConfigStoreTests"`

Expected: FAIL to compile — `cannot find 'RemoteConfigStore' in scope`.

- [ ] **Step 3: Write the store**

Create `On Board/Configuration/RemoteConfigStore.swift`:

```swift
//
//  RemoteConfigStore.swift
//  On Board
//
//  Owns the fetch, caching, and resolution of RemoteConfig.
//
//  Persisted in UserDefaults rather than CacheEnvelope on purpose: the envelope
//  is cleared on sign-out and hydrated asynchronously by BoardStore, while
//  config must survive sign-out and be readable synchronously before sign-in —
//  the version gate and any auth-flow flag matter precisely when signed out.
//  See CLAUDE.md's cache section for why this is a deliberate exception.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "org.onboardapp.onboard", category: "RemoteConfig")

@Observable
@MainActor
final class RemoteConfigStore {
    static let storageKey = "remoteConfig.values"
    private static let identityKey = "remoteConfig.installIdentity"

    private(set) var config: RemoteConfig = .empty

    /// Stable per-install id used to bucket feature flags before sign-in, so a
    /// staged rollout behaves consistently on the sign-in screen too.
    private(set) var installIdentity: UUID

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.string(forKey: Self.identityKey),
           let identity = UUID(uuidString: stored) {
            installIdentity = identity
        } else {
            let identity = UUID()
            defaults.set(identity.uuidString, forKey: Self.identityKey)
            installIdentity = identity
        }

        if let stored = defaults.object(forKey: Self.storageKey) as? [String: String] {
            config = RemoteConfig(values: stored)
        }
    }

    /// Fire-and-forget. Never throws to the caller and never blocks rendering —
    /// a failed fetch simply leaves the last-known (or compiled-default) config
    /// in place, which is always a usable app.
    func refresh() async {
        guard let client = SupabaseClientFactory.client(for: .current) else { return }
        do {
            let values: [String: String] = try await client
                .rpc("get_app_config")
                .execute()
                .value
            apply(values)
        } catch {
            logger.debug("Remote config fetch failed, keeping last known: \(error.localizedDescription)")
        }
    }

    /// Applies fetched values, writing to storage only when something actually
    /// changed — this runs on every foreground, and most calls just reconfirm
    /// what's already stored.
    func apply(_ values: [String: String]) {
        let updated = RemoteConfig(values: values)
        guard updated != config else { return }
        config = updated
        defaults.set(values, forKey: Self.storageKey)
    }

    /// Resolves a flag against the signed-in user when there is one, and the
    /// per-install identity otherwise.
    func isEnabled(_ flag: FeatureFlag, for userID: UUID?) -> Bool {
        config.isEnabled(flag, for: userID ?? installIdentity)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/RemoteConfigStoreTests"`

Expected: PASS, 5 tests.

- [ ] **Step 5: Inject the store at the root**

In `On Board/On_BoardApp.swift`, find where the other stores (`AuthStore`, `BoardStore`, `OnboardingStore`, `NetworkMonitor`) are created as `@State` and injected with `.environment(...)`. Add alongside them:

```swift
    @State private var remoteConfig = RemoteConfigStore()
```

and in the same `.environment(...)` chain applied to `RootView`:

```swift
        .environment(remoteConfig)
```

- [ ] **Step 6: Fetch at launch and on foreground**

In `On Board/Views/Shared/RootView.swift`, add the environment property alongside the existing ones (near line 15):

```swift
    @Environment(RemoteConfigStore.self) private var remoteConfig
```

Add a launch fetch to the view's existing `.task` modifier — or, if there isn't one on the root `body`, add:

```swift
        .task { await remoteConfig.refresh() }
```

Then extend the existing `scenePhase` handler (line 109). Note the config refresh goes **above** the `auth.isSignedIn` guard, since config must update for signed-out users too:

```swift
        .onChange(of: scenePhase) { _, phase in
            guard didBootstrap, phase == .active else { return }
            network.recheck()
            // Above the isSignedIn guard on purpose — the version gate and any
            // auth-flow flag have to stay fresh for signed-out users too.
            Task { await remoteConfig.refresh() }
            guard auth.isSignedIn else { return }
            Task { await onboarding.refreshOnForeground() }
        }
```

- [ ] **Step 7: Verify the build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add "On Board/Configuration/RemoteConfigStore.swift" "On Board/On_BoardApp.swift" "On Board/Views/Shared/RootView.swift" "On BoardTests/RemoteConfigTests.swift"
git commit -m "Fetch and cache remote config at launch and on foreground"
```

---

### Task 5: Version gate and app-version telemetry

**Files:**
- Create: `supabase/migrations/<timestamp>_device_token_app_version.sql`
- Modify: `On Board/Notifications/NotificationService.swift:110-122`
- Create: `On Board/Views/Shared/UpdateAvailableModifier.swift`
- Modify: `On Board/Views/Shared/RootView.swift`
- Test: `On BoardTests/RemoteConfigTests.swift`

**Interfaces:**
- Consumes: `RemoteConfig.minSupportedVersion`, `RemoteConfig.recommendedVersion`, `AppLinks.appStoreURL` (added by the forward-compatible-decoding plan, Task 5).
- Produces: `AppVersion.isOlder(_ lhs: String, than rhs: String) -> Bool`, `enum UpdateRequirement { case none, recommended, required }`, `RemoteConfig.updateRequirement(forCurrentVersion:) -> UpdateRequirement`, and `View.updatePrompt(_:)`.

- [ ] **Step 1: Write the failing test**

Append to `On BoardTests/RemoteConfigTests.swift`:

```swift
struct AppVersionComparisonTests {
    @Test func comparesNumericallyNotLexically() {
        // The bug this pins: "1.10" < "1.9" as a string comparison.
        #expect(AppVersion.isOlder("1.9", than: "1.10"))
        #expect(!AppVersion.isOlder("1.10", than: "1.9"))
    }

    @Test func equalVersionsAreNotOlder() {
        #expect(!AppVersion.isOlder("1.1.1", than: "1.1.1"))
    }

    @Test func handlesDifferingComponentCounts() {
        #expect(AppVersion.isOlder("1.1", than: "1.1.1"))
        #expect(!AppVersion.isOlder("1.1.1", than: "1.1"))
    }

    @Test func malformedVersionsAreNeverTreatedAsOlder() {
        // Never lock someone out because a version string was garbled.
        #expect(!AppVersion.isOlder("banana", than: "1.1.1"))
    }
}

struct UpdateRequirementTests {
    @Test func absentKeysRequireNothing() {
        #expect(RemoteConfig.empty.updateRequirement(forCurrentVersion: "1.1") == .none)
    }

    @Test func belowRecommendedIsSoft() {
        let config = RemoteConfig(values: ["recommended_version": "1.2"])
        #expect(config.updateRequirement(forCurrentVersion: "1.1") == .recommended)
    }

    @Test func belowMinimumIsBlockingAndBeatsRecommended() {
        let config = RemoteConfig(values: [
            "min_supported_version": "1.2",
            "recommended_version": "1.3"
        ])
        #expect(config.updateRequirement(forCurrentVersion: "1.1") == .required)
    }

    @Test func atOrAboveBothRequiresNothing() {
        let config = RemoteConfig(values: [
            "min_supported_version": "1.1",
            "recommended_version": "1.1"
        ])
        #expect(config.updateRequirement(forCurrentVersion: "1.1") == .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/AppVersionComparisonTests"`

Expected: FAIL to compile — `cannot find 'AppVersion' in scope`.

- [ ] **Step 3: Write the version comparison and requirement**

Append to `On Board/Configuration/RemoteConfig.swift`:

```swift
// MARK: - Version gating

enum AppVersion {
    /// Current `CFBundleShortVersionString`, e.g. "1.1.1".
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Numeric, component-wise comparison. A plain string compare would read
    /// "1.10" as older than "1.9" and lock users out of a *newer* build.
    ///
    /// Returns `false` for anything unparseable — never gate someone out of the
    /// app because a version string was malformed.
    nonisolated static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) }
        let right = rhs.split(separator: ".").map { Int($0) }
        guard !left.contains(nil), !right.contains(nil), !left.isEmpty, !right.isEmpty else {
            return false
        }
        let l = left.compactMap { $0 }
        let r = right.compactMap { $0 }
        for index in 0..<max(l.count, r.count) {
            let a = index < l.count ? l[index] : 0
            let b = index < r.count ? r[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}

enum UpdateRequirement: Equatable, Sendable {
    case none
    /// Dismissible prompt. The default posture.
    case recommended
    /// Blocking screen. Reserved for builds that are actively harmful —
    /// data corruption, not cosmetic bugs.
    case required
}

extension RemoteConfig {
    func updateRequirement(forCurrentVersion current: String = AppVersion.current) -> UpdateRequirement {
        if let minimum = minSupportedVersion, AppVersion.isOlder(current, than: minimum) {
            return .required
        }
        if let recommended = recommendedVersion, AppVersion.isOlder(current, than: recommended) {
            return .recommended
        }
        return .none
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/AppVersionComparisonTests" -only-testing "On BoardTests/UpdateRequirementTests"`

Expected: PASS, 8 tests.

- [ ] **Step 5: Write the update prompt modifier**

Create `On Board/Views/Shared/UpdateAvailableModifier.swift`:

```swift
//
//  UpdateAvailableModifier.swift
//  On Board
//
//  Surfaces the version gate. `.recommended` is a dismissible alert; `.required`
//  is a full-screen cover with no way out but the App Store.
//
//  A dismissed soft prompt stays dismissed for that version — nagging on every
//  foreground would train people to dismiss without reading, which is exactly
//  the reflex you don't want when a `.required` prompt eventually appears.
//

import SwiftUI

struct UpdateAvailableModifier: ViewModifier {
    let requirement: UpdateRequirement

    @Environment(\.openURL) private var openURL
    @AppStorage("update.dismissedForVersion") private var dismissedForVersion = ""
    @State private var showingSoftPrompt = false

    func body(content: Content) -> some View {
        content
            .onChange(of: requirement, initial: true) { _, requirement in
                showingSoftPrompt = requirement == .recommended
                    && dismissedForVersion != AppVersion.current
            }
            .alert("Update available", isPresented: $showingSoftPrompt) {
                Button("Update") { openURL(AppLinks.appStoreURL) }
                Button("Not now", role: .cancel) {
                    dismissedForVersion = AppVersion.current
                }
            } message: {
                Text("A newer version of On Board is available with fixes and improvements.")
            }
            .fullScreenCover(isPresented: .constant(requirement == .required)) {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Update required")
                        .font(.title2.weight(.semibold))
                    Text("This version of On Board is out of date. Update to keep using the app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                    Button {
                        openURL(AppLinks.appStoreURL)
                    } label: {
                        Text("Update On Board").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .interactiveDismissDisabled()
            }
    }
}

extension View {
    func updatePrompt(_ requirement: UpdateRequirement) -> some View {
        modifier(UpdateAvailableModifier(requirement: requirement))
    }
}
```

- [ ] **Step 6: Attach it in `RootView`**

In `On Board/Views/Shared/RootView.swift`, add to the root `body`'s modifier chain, after the `scenePhase` handler:

```swift
        .updatePrompt(remoteConfig.config.updateRequirement())
```

- [ ] **Step 7: Write the telemetry migration**

Create `supabase/migrations/<timestamp>_device_token_app_version.sql`:

```sql
-- Record which app version each device is running, so a staged rollout or a
-- min-version gate can be reasoned about before it is used. Without this there
-- is no way to answer "what share of users can even read my config?".
alter table public.device_tokens add column if not exists app_version text;

-- The parameter list changes, so this is a drop + create rather than a replace.
-- p_app_version defaults to null, so a client still on the one-argument call
-- keeps working unchanged.
drop function if exists public.register_device_token(text);

create function public.register_device_token(
  p_token text,
  p_app_version text default null
)
returns void
language sql
security definer
set search_path to 'public'
as $$
  insert into device_tokens (user_id, token, app_version, updated_at)
  values (auth.uid(), p_token, p_app_version, now())
  on conflict (token)
  do update set user_id = auth.uid(),
                -- coalesce so an older client sending null can't wipe a version
                -- a newer client already recorded for this device.
                app_version = coalesce(excluded.app_version, device_tokens.app_version),
                updated_at = now();
$$;

revoke all on function public.register_device_token(text, text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;
```

- [ ] **Step 8: Apply the migration and verify**

Apply via the Supabase MCP `apply_migration` with name `device_token_app_version`, then rename the local file to the returned version stamp.

Verify with `execute_sql`:

```sql
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'device_tokens' and column_name = 'app_version';
```

Expected: one row.

- [ ] **Step 9: Send the version from the client**

In `On Board/Notifications/NotificationService.swift`, replace lines 119–121:

```swift
        _ = try? await client
            .rpc("register_device_token", params: ["p_token": hex])
            .execute()
```

with:

```swift
        _ = try? await client
            .rpc("register_device_token", params: [
                "p_token": hex,
                "p_app_version": AppVersion.current
            ])
            .execute()
```

- [ ] **Step 10: Verify the build and full suite**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`

Expected: `** BUILD SUCCEEDED **`.

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`

Expected: whole suite passes.

- [ ] **Step 11: Commit**

```bash
git add "On Board/Configuration/RemoteConfig.swift" "On Board/Views/Shared/UpdateAvailableModifier.swift" "On Board/Views/Shared/RootView.swift" "On Board/Notifications/NotificationService.swift" "On BoardTests/RemoteConfigTests.swift" supabase/migrations/
git commit -m "Add version gate and report app version with device tokens"
```

---

### Task 6: Route compiled constants through config

**Files:**
- Modify: `On Board/Views/Feed/ContentView.swift:316`
- Modify: `On Board/Models/OnboardingStatus.swift:109-138`
- Modify: `On Board/Views/Auth/SignInView.swift:56`, `On Board/Views/Settings/LinkSignInMethodView.swift:36`, `On Board/Views/Onboarding/OnboardingSchoolEmailStepView.swift:244,253`
- Modify: `On Board/Views/Post/CommentComposerState.swift:29`, `On Board/Views/Profile/ProfileDraft.swift:19-20`

**Interfaces:**
- Consumes: `RemoteConfigStore.config`.
- Produces: no new API. Each constant keeps its current value as the fallback, so behavior is unchanged until a key is seeded.

Do these one at a time, building between each. Every one must be behavior-identical with an empty config.

- [ ] **Step 1: Feed poll interval**

In `On Board/Views/Feed/ContentView.swift`, add the environment property alongside the existing ones:

```swift
    @Environment(RemoteConfigStore.self) private var remoteConfig
```

Replace line 316:

```swift
                try? await Task.sleep(for: .seconds(45))
```

with:

```swift
                try? await Task.sleep(for: .seconds(remoteConfig.config.feedPollSeconds))
```

- [ ] **Step 2: OTP cooldown, single-sourced**

The cooldown is currently duplicated across four sites with two different values (60s in `SignInView.swift:56` and `LinkSignInMethodView.swift:36`, 30s in `OnboardingSchoolEmailStepView.swift:244` and `:253`). Single-source it while wiring.

Delete `private let otpCooldownSeconds = 60` from both `SignInView.swift` and `LinkSignInMethodView.swift`. In all four call sites, add the environment property and read `remoteConfig.config.otpCooldownSeconds`, passing it to `resendCooldown.start(duration:destination:)`.

> This changes the school-email resend cooldown from 30s to 60s. That is an
> intentional consolidation, not a regression — flag it in the PR description so
> it isn't mistaken for a bug.

- [ ] **Step 3: Referral thresholds**

`ReferralRewards` (`On Board/Models/OnboardingStatus.swift:109`) is a static enum with no access to the environment. Convert its two functions to take the values as parameters rather than reading globals:

```swift
enum ReferralRewards {
    static let oneMonthThreshold = 4
    static let threeMonthThreshold = 5
    static let disclosureThreshold = 3

    static func earnedFirstClassMonths(
        for count: Int,
        oneMonth: Int = oneMonthThreshold,
        threeMonth: Int = threeMonthThreshold
    ) -> Int {
        if count >= threeMonth { return 3 }
        if count >= oneMonth { return 1 }
        return 0
    }

    static func milestoneText(
        for count: Int,
        oneMonth: Int = oneMonthThreshold,
        threeMonth: Int = threeMonthThreshold,
        disclosure: Int = disclosureThreshold
    ) -> String? {
        switch earnedFirstClassMonths(for: count, oneMonth: oneMonth, threeMonth: threeMonth) {
        case 3:
            return "🏆 3 free months of First Class earned!"
        case 1:
            return "🎟️ Free month of First Class earned — 1 more invite makes it 3!"
        default:
            guard count >= disclosure else { return nil }
            return "✨ 1 more invite to earn a free month of On Board First Class"
        }
    }
}
```

The defaults keep every existing call site compiling and behaving identically. In `OnboardingWaitlistStepView`, pass the config values explicitly.

- [ ] **Step 4: Field limits**

`CommentComposerState.maxLength` (`:29`) and `ProfileDraft.displayNameLimit`/`bioLimit` (`:19-20`) are static constants used by `FieldLimitCaption`. Convert each type to take its limit as an `init` parameter defaulting to the current constant, and pass `remoteConfig.config.commentMaxLength` / `.displayNameMaxLength` / `.bioMaxLength` at the construction sites.

> **Server authority:** if `comments.body` or `profiles.bio` has a server-side
> length constraint, raising the client value alone produces a rejected write with
> a confusing error. Check the column constraints before ever seeding a value
> larger than the current one.

- [ ] **Step 5: Verify nothing changed behaviorally**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`

Expected: whole suite passes. `CommentComposerStateTests` in particular must still pass unchanged — it asserts against the 280 limit.

Run the app in the simulator with no config keys seeded. The feed polls, the composer enforces 280, the OTP resend counts down. Any observable difference means a default is wrong.

- [ ] **Step 6: Commit**

```bash
git add "On Board/Views" "On Board/Models/OnboardingStatus.swift"
git commit -m "Route feed poll, OTP cooldown, referral thresholds and field limits through config"
```

---

### Task 7: Document the conventions

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add to CLAUDE.md**

Under **Key Conventions**:

```markdown
- **Remote config lives in `Configuration/RemoteConfig.swift` and nowhere else.**
  It is the only file containing config key literals; call sites read typed
  accessors (`config.feedPollSeconds`), never strings. Every accessor falls back
  to the value that was compiled in, so a server returning `{}` behaves exactly
  like a build with no remote config. Adding a key means: add it to the
  `get_app_config` allowlist migration, add a typed accessor with the current
  hardcoded value as its fallback, then read it at the call site.
- **Config is cached in `UserDefaults`, deliberately not in `CacheEnvelope`.**
  The envelope is cleared on sign-out and hydrated async by `BoardStore`; config
  must survive sign-out and be readable synchronously before sign-in, because
  the version gate and auth-flow flags matter precisely when signed out. This is
  a documented exception to the "one envelope, one file" rule, not a second cache
  for board data.
- **Every new feature is born behind a `FeatureFlag`, defaulted `false`.** Ship it
  inert on the normal release cadence and switch it on when ready — that is what
  decouples "the feature is done" from "Apple approved the build". Flags added
  retroactively for existing surfaces default `true`, since the compiled default
  must always equal what the app already does. Bucketing is salted per flag
  (`RemoteConfig.bucket(_:salt:)`); without the salt the same unlucky cohort
  receives every staged rollout forever.
- **Version comparison uses `AppVersion.isOlder`, never string comparison** —
  `"1.10" < "1.9"` lexically, which would lock users out of a newer build.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document remote config and feature flag conventions"
```

---

## Verification

- [ ] `select public.get_app_config();` returns `{}` — no keys seeded for the 1.1.1 submission.
- [ ] `board_timezone` does **not** appear in `get_app_config()` output.
- [ ] Full test suite passes with `-parallel-testing-enabled NO`.
- [ ] The app runs in the simulator, signed out and signed in, with no config seeded — behavior identical to 1.1.
- [ ] Seed `feed_poll_seconds = 120`, foreground the app, confirm the poll interval changes. Delete the key afterward.
- [ ] `AppLinks.appStoreURL` has the real Apple ID, not the placeholder.

## Post-ship rollout

1. Ship 1.1.1 with no keys seeded.
2. Confirm `select app_version, count(*) from device_tokens group by 1;` shows 1.1.1 installs landing.
3. Seed `feed_poll_seconds` and verify on a real device — this is the proof the path works end to end.
4. Seed the remaining constants, then each flag at `on` (matching current behavior), so the flag path is exercised before it's ever needed at `off`.
