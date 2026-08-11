# On Board — Release Agility & Forward Compatibility

**Date:** 2026-08-01
**Status:** Proposed
**Target build:** 1.1.1 (current shipped: 1.1, build 1)

## Goal

Decouple two pairs of events that are currently welded together:

- **"Feature is finished"** from **"Apple approved it."**
- **"Bug found"** from **"new build shipped."**

Concretely: a finished feature should ship inert on the normal release cadence
and be switched on when *we* decide, and a bad surface should be switchable off
in minutes without a release. Neither is possible today — the app has no remote
control of any kind.

## Problem

On Board is live with zero remote levers. Four distinct gaps:

1. **Nothing can be tuned.** Every threshold and interval is compiled. Several
   are documented as mirroring server rules (`Profile.handleChangeAvailableAt`,
   `BoardPhase` vs. `app_config.board_timezone`) — each is a latent split-brain
   only a build can resolve.

2. **Nothing can be turned off.** A broken surface stays broken until review
   clears. On a weekly board that clears Monday, a Tuesday bug costs the week,
   and the content is unrecoverable.

3. **Nothing can be shipped dark.** Any finished feature is visible the instant
   the build goes live, so its launch date is whatever Apple decides.

4. **Nothing is observed.** No crash reporting, no analytics, no remote logging —
   only local `OSLog`. Today a bug affecting a third of users is discovered by
   text message. This makes the other three gaps worse: levers are useless
   without a signal telling you to pull them.

Separately and urgently: **five wire-crossing enums fail closed.** Adding any new
value to any of them breaks every client that hasn't updated, two of them
catastrophically. This blocks roadmap work (alumni boards need a new onboarding
step) and must ship before the value that triggers it can exist.

## Non-goals

- **No native code replacement.** Guideline 2.5.2 permits downloaded code only in
  JavaScriptCore/WebKit. Third-party WebAssembly approaches (Patch) rest on a
  DPLA §3.3.1(B) reading with no published case history and are explicitly
  rejected for now — the downside is app removal, against an upside of one day of
  review latency.
- **No server-driven UI renderer.** Deferred. Revisit only if a real second use
  case appears.
- **No general remote string table.** One locale doesn't justify making the app
  un-greppable.
- **No rescue from launch crashes.** Anything failing before config resolves needs
  a build. The config path must never gate first render.

## Scope — seven parts

Parts 1–5 are code. Part 6 is the initial consumer set. Part 7 is process.

---

## Part 1 — Forward-compatible wire decoding

Prerequisite for everything on the roadmap that adds a wire value. All five enums
are `String`-backed with fail-closed decoding; because each is decoded inside an
array (`[RemotePostRow]`, `[UserReactionRow]`), one unknown value fails the
**entire** response, not one row.

| Enum | Location | Blast radius | Fallback policy |
|---|---|---|---|
| `OnboardingStep` | `Models/OnboardingStep.swift:8` | Users locked out of the app entirely | New `.unrecognized` case → update prompt. **No generic default** — see below |
| `BoardWeek.Status` | `Models/BoardWeek.swift:12` | Board fetch fails; app dead | Unknown → `.archived` (read-only). `init(from:)` already hand-written at line 72 |
| `PostTone` | `Models/PostTone.swift:15` | Feed dead for the week | Unknown → deterministic known tone |
| `Reaction` | `Models/Reaction.swift:13` | Counts path already safe; `UserReactionRow.type` is not | Unknown → drop |
| `CommentVote` | `Models/Comment.swift:83` | Comment votes dead | Unknown → drop (treat as no vote) |

**`AuthProvider` needs no change.** Every wire path routes through the failable
`init?(supabaseProvider:)` (`SupabaseAuthService.swift:477,490`,
`LinkedIdentity.swift:22`), which already returns `nil` on unknown values. Its
`Codable` decode (`AuthSession.swift:81`) is used only for the locally-persisted
session, written and read by the same build, so there is no cross-version risk.

### `PostTone` — deterministic mapping

```swift
extension PostTone {
    nonisolated init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PostTone(rawValue: raw) ?? PostTone.stableFallback(for: raw)
    }

    nonisolated static func stableFallback(for raw: String) -> PostTone {
        let seed = raw.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFFFF }
        return allCases[seed % allCases.count]
    }
}
```

**Never seed from `String.hashValue`** — Swift seeds it per process, so the same
unknown tone would render a different color on every launch. This trap recurs in
Part 3's bucketing; use the same stable helper.

### `OnboardingStep` — needs care, not a blanket fallback

The riskiest of the six and the one that must *not* get a generic default.
Mapping an unknown step to `.complete` would admit users who haven't finished
onboarding; mapping to any specific step could trap them in a loop.

The mapping is already asymmetric: `.contentPreferences` and `.graduation` are
client-inserted with no backing `onboarding_step` Postgres value. Policy:

- Decode unknown → a new `.unrecognized` case.
- `OnboardingStore` treats `.unrecognized` as "this client is too old to complete
  onboarding" and shows the update prompt from Part 4 rather than a broken step.

This is the one place where degrading gracefully means *telling the user to
update*, because there is no correct local behavior.

### Reaction / vote rows

Unknown reactions must be **dropped, not mapped** — mapping would inflate another
reaction's count. Change `UserReactionRow.type` and `UserCommentVoteRow.vote`
(`Supabase/SupabaseBoardService.swift:100-108`) to carry raw `String` and filter
at the assembly site with `compactMap`, matching the idiom already correct in
`RemotePostRow.decodeReactionCounts`.

---

## Part 2 — Remote config read path

### Server

Reuse `public.app_config` (`key text, value text, updated_at`) unchanged. The
migration adds only the function.

```sql
create or replace function public.get_app_config()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.app_config
  where key like 'flag_%' or key in (
    'min_supported_version', 'recommended_version',
    'feed_poll_seconds', 'otp_cooldown_seconds',
    'referral_one_month_threshold', 'referral_three_month_threshold',
    'referral_disclosure_threshold',
    'board_clearing_soon_hours', 'board_final_hour_lockout_hours',
    'handle_change_window_days', 'handle_change_max_per_window',
    'comment_max_length', 'bio_max_length', 'display_name_max_length',
    'max_cached_archive_weeks',
    'referral_share_message', 'referral_share_message_instant'
  );
$$;

revoke all on function public.get_app_config() from public;
grant execute on function public.get_app_config() to anon, authenticated;
```

Two decisions worth recording:

- **`anon` gets EXECUTE, not just `authenticated`.** The existing table policy is
  `authenticated`-only. The version gate and any auth-flow kill switch must work
  *before* sign-in — a broken sign-in is exactly when they're needed. Follows the
  `check_email_exists` precedent.
- **Explicit allowlist, never `select *`.** `board_timezone` and every future
  server-only key would otherwise leak to anyone holding the anon key. The
  `flag_%` prefix is deliberately open so a new flag needs no migration; flags are
  boolean/percentage and carry no secrets by construction.

### Client

```swift
struct RemoteConfig: Sendable, Equatable {
    private let values: [String: String]
    static let empty = RemoteConfig(values: [:])

    var feedPollSeconds: TimeInterval { double("feed_poll_seconds") ?? 45 }
    var otpCooldownSeconds: Int { int("otp_cooldown_seconds") ?? 60 }
    // ...one typed accessor per key
}
```

The wire is an untyped string map so unknown keys are ignored (forward
compatible) and missing keys fall back (backward compatible). **Call sites never
see a string** — string keys are confined to this one file.

### Fallback rules — non-negotiable

1. Every accessor returns a compiled default when the key is absent, unparseable,
   or the fetch failed. A server returning `{}` must be indistinguishable from
   today's build.
2. Fetch is fire-and-forget; it never blocks first render.
3. The default **is** current shipped behavior, always. No accessor may return a
   value that causes the caller to skip behavior it does today.
4. Values are advisory. Any server-enforced limit stays server-authoritative; a
   stale client is confusing at worst, never wrong.

### Fetch and cache lifecycle

- Fetched at launch and on `RootView`'s existing `scenePhase` foreground handler.
  No new timer.
- **Cached in `UserDefaults`, deliberately *not* in `CacheEnvelope`.** CLAUDE.md's
  "one envelope, one file" rule governs cached *board entities*; remote config has
  different lifetime semantics and does not belong there:
  - `CacheEnvelope` is deleted by `clearDiskCache()` on sign-out. Config must
    survive sign-out — it is app configuration, not account data, and leaking
    nothing between accounts is not a concern for values every client receives.
  - `CacheEnvelope` is `BoardStore`-owned and hydrated asynchronously off-main.
    The version gate and any auth-flow flag must be readable **before**
    sign-in and **synchronously** at launch.
  - The payload is ~20 short strings. It needs no async hydration.
- Owned by a `RemoteConfigStore` (`@Observable @MainActor`) injected at the root
  alongside the existing stores, not by `BoardStore`.
- Write to `UserDefaults` only when the fetched config **differs** from what's
  stored, matching the `loadComments` / `refreshPopScore` guard.

---

## Part 3 — Feature flags with staged rollout

This is what makes "finished feature waiting on Apple" a solved problem. Every
future feature ships behind a flag, defaulted off, and is switched on when we
choose — days or weeks after the build cleared review.

### Wire format

Keys are `flag_<name>`; values are `off`, `on`, or an integer `0`–`100` for a
percentage rollout.

### Client

```swift
enum FeatureFlag: String, CaseIterable {
    case zoomTransition, glassEffects, postPhotoAttachments, hostVoice
    // future features register here at birth, defaulted off

    /// Behavior when the server says nothing. Existing shipped surfaces
    /// default `true`; unlaunched features default `false`.
    var compiledDefault: Bool { ... }
}

extension RemoteConfig {
    func isEnabled(_ flag: FeatureFlag, for identity: UUID) -> Bool {
        switch values["flag_\(flag.rawValue)"] {
        case "on":  return true
        case "off": return false
        case let raw?:
            guard let pct = Int(raw) else { return flag.compiledDefault }
            return bucket(identity, salt: flag.rawValue) < pct
        case nil:   return flag.compiledDefault
        }
    }
}
```

Three design points that matter:

- **Bucketing is salted per flag.** Hash `identity + flag.rawValue`, not identity
  alone. Without the salt the same unlucky 10% of users receive every staged
  rollout, which turns a sampling strategy into a single permanently-experimented-
  on cohort.
- **Stable hash, not `hashValue`.** Same per-process seeding trap as Part 1. Use
  FNV-1a over UTF-8. A user must land in the same bucket on every launch, or a
  feature flickers in and out between app opens.
- **Signed-out users bucket on a persisted install UUID**, generated once and
  stored in the keychain, so the flag system works before sign-in.

### Initial flags

Existing surfaces worth a switch, ranked by risk:

1. `zoomTransition` — four documented landmine categories in CLAUDE.md, and the
   fallback (plain push) is trivially correct.
2. `glassEffects` — the non-glass path already ships to iOS 18 users, so the
   fallback is proven code rather than a dormant branch.
3. `postPhotoAttachments` — lets an upload or moderation incident degrade to
   text-only posting instead of taking the app down.
4. `hostVoice` — audio synthesis is a plausible performance surface; muting is
   cheap.

---

## Part 4 — Version gate and telemetry

### Telemetry

Add `app_version text` to `device_tokens`, set by `NotificationService` on
registration. Today nothing can answer "what fraction of users can even read my
config?" — which is what makes every other lever trustworthy.

### Gate

Compare `CFBundleShortVersionString` against config using
`compare(_:options: .numeric)`, never string comparison ("1.10" must sort above
"1.9"). Ship both variants, default to soft:

- **`recommended_version`** — dismissible prompt. Default posture.
- **`min_supported_version`** — blocking screen linking to the App Store.
  Reserved for actively harmful builds, and the destination for Part 1's
  `OnboardingStep.unrecognized`.

Both keys absent means neither appears — the shipped 1.1.1 state.

---

## Part 5 — Observability

Without this the rest is a dashboard with no instruments. Requirements: crash
reports with symbolication, non-fatal error capture, and enough breadcrumbs to
tell *which* surface broke.

**Recommended: Sentry** (`sentry-cocoa` via SPM). Free tier is generous at this
scale, gives crashes + non-fatals + release-health (crash-free session rate per
app version, which is exactly the signal a staged rollout needs), and ships its
own privacy manifest.

**Zero-dependency alternative: MetricKit.** Apple-native, no SDK, crash
diagnostics and performance payloads posted to a Supabase table. Fits the app's
minimal-dependency posture, but payloads arrive once per ~24h and you build the
receiver and any dashboard yourself. Acceptable only if adding an SDK is
unacceptable; the 24h delay defeats fast incident response.

Either way:

- Update `PrivacyInfo.xcprivacy` and review App Store privacy nutrition labels.
- Scrub PII — no handles, emails, post bodies, or school domains in events.
- Tag every event with app version and the active flag set, or you cannot
  correlate a crash spike with the rollout that caused it.

---

## Part 6 — Constants routed through config

Each keeps its current value as the compiled default, so shipping changes nothing
observable.

| Constant | Location | Key |
|---|---|---|
| Feed poll `45s` | `ContentView.swift:316` | `feed_poll_seconds` |
| Referral thresholds `4 / 5 / 3` | `OnboardingStatus.swift:110` | `referral_*_threshold` |
| `BoardPhase` 3h / 1h | `BoardSchedule.swift` | `board_clearing_soon_hours`, `board_final_hour_lockout_hours` |
| Handle-change `14d` / max `2` | `Profile.swift:118` | `handle_change_window_days`, `handle_change_max_per_window` |
| OTP cooldown `60s` / `30s` | `SignInView.swift:56`, `LinkSignInMethodView.swift:36`, `OnboardingSchoolEmailStepView.swift:244` | `otp_cooldown_seconds` |
| Comment `280`, bio `300`, name `50` | `CommentComposerState.swift:29`, `ProfileDraft.swift:19` | `*_max_length` |
| `maxCachedArchiveWeeks 3` | `BoardStore.swift:121` | `max_cached_archive_weeks` |
| `shareMessage` copy | `OnboardingStatus.swift:101` | `referral_share_message*` |

Routing all of these rather than a token two is deliberate: **dormant plumbing is
plumbing you don't know works.** If nothing exercises the path under real traffic,
the first time it matters is the first time it runs.

**Incidental cleanup in scope:** the OTP cooldown is duplicated across four call
sites with two different values (60s and 30s). Single-source it while wiring.

**Out of scope — already server-side:** moderation strictness (LLM judge runs in
the backend) and push behavior (gated by `user_settings` and the Edge Function
`switch`).

---

## Part 7 — Process

Code alone doesn't produce release agility. Three habits:

1. **Every new feature is born behind a flag**, registered in `FeatureFlag` and
   defaulted `false`, merged and shipped inert. This is the actual answer to
   "Apple is taking a while" — the code is already on devices before the feature
   is announced.
2. **Turn on App Store Connect phased release.** A free Apple feature: a 7-day
   automatic ramp for auto-updating users, pausable at any point. Staged rollout
   for the binary itself, complementing flags for features. Zero code.
3. **Ship on a cadence, not on completion.** Submitting regularly — even a small
   build — keeps review off the critical path, because the next train is always
   close. This is the whole mechanism behind how large apps appear to launch
   without review.

---

## Testing

Swift Testing (`@Test`, `#expect`), fixtures through mocks.

- **Lenient decode, per enum:** an array containing one unknown value decodes
  fully with the documented fallback applied; unknown reactions/votes are dropped
  rather than mapped; `OnboardingStep` unknown yields `.unrecognized`.
- **Determinism:** the same unknown tone maps to the same tone across repeated
  decodes — pins the stable-seed requirement.
- **Config fallback:** `RemoteConfig.empty` returns every compiled default;
  unparseable values (`"abc"` for an Int key) fall back rather than crash.
- **Flag bucketing:** stable across repeated calls for one identity; a 0% flag is
  off for all identities and 100% is on for all; two different flags at 10% select
  measurably different cohorts (pins the per-flag salt).
- **Version comparison:** `1.10 > 1.9`; equal does not gate; absent keys do not
  gate.
- **Cache round-trip:** an envelope with config encodes and decodes; an envelope
  written without the field still decodes.

## Rollout

1. Ship 1.1.1 with **no config keys seeded**. Behavioral no-op, low-risk review.
2. Confirm installs are landing via `device_tokens.app_version`, and that Sentry
   is receiving sessions.
3. Seed one harmless key (`feed_poll_seconds`) and verify on a real device. This
   is the proof the path works end to end.
4. Seed the remaining constants, then the flags at `on` (matching current
   behavior) so the flag path is exercised before it's ever needed at `off`.

## Deferred

- Server-driven announcement card — revisit once there's a second use case.
- Any general SDUI renderer.
- Third-party OTA (Patch et al.) — revisit only with published case history and
  at a scale where review latency has measurable cost.

## Guideline compliance

Everything here is remote **data** parameterizing shipped native code — the same
category as the existing `legal_documents` → `PolicyView` and `prompt_queue` →
`WeeklyPromptBanner` paths. Nothing downloads or interprets code, so 2.5.2 is not
engaged.

On 2.3.1 (hidden or undocumented features): staged rollout behind flags is
standard practice and accepted. The line is intent — a flag must never conceal
functionality that would be rejected on review and then be enabled afterward.
