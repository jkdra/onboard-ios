# Dark Launch Roadmap — from flag to activation to adoption

**Date:** 2026-08-02
**Status:** Proposed
**Context:** written after the 1.1.1 release-agility work landed on `chore/observability`

---

## Part 1 — What Meta actually does

Three separate mechanisms, usually conflated into one.

### Gatekeeper — the flag system

Facebook's dark-launch tool is literally called **Gatekeeper**, because it controls
consumer access to each feature. The pattern: a feature is deployed but hidden;
the system may still *run* it in the background to measure performance while
nobody can see it. Rollout then proceeds in deliberate increments — internal
employees first, then 1%, 5%, 30%, and up. Increments can go as fine as 0.1%,
specifically to catch **non-linear effects** — things that behave fine at 1% and
fall over at 20% because of load, network effects, or moderation volume.

The operational property that matters: an engineer can make a change, get
feedback from thousands of internal users, and **roll it back within an hour**.

### Bloks — server-driven UI

The server sends a tree of "blocks." Each node names a component and its props.
The client walks the tree and renders. A **component registry** maps server-sent
names (`"ProductCarousel"`) to real native components compiled into the app.

The critical constraint, and the thing most summaries omit: **the schema is
implemented on both server and client.** You can only compose what the client
already knows how to draw. New component = new build. Their remote surface is
enormous, but it has a hard edge, and that edge is a native release.

### The release train

Meta moved facebook.com to quasi-continuous "push from master" in 2016, ramped
deliberately — 50% of employees, then 0.1% → 1% → 10% of production traffic —
each step testing whether the *tooling* could handle the higher frequency, not
just whether the code worked. Mobile release trains at this tier run weekly or
biweekly: code makes the cut or waits for the next train.

This is what makes review latency irrelevant. It is never "wait for review to
launch." It is "the code shipped three trains ago; today someone flipped a row."

### What this means for a solo developer

Bloks is a multi-year investment by an org with hundreds of engineers on
developer infrastructure. That is arithmetic, not brilliance: when a week-faster
launch is worth millions, the amortization is trivially correct.

The transferable parts are **Gatekeeper** (cheap — you now have it) and **the
train** (free — it's a habit). Bloks is not transferable and should not be
attempted.

---

## Part 2 — Where On Board actually is

### The branches (corrected 2026-08-02)

An earlier revision of this document claimed neither feature branch contained
feature code. **That was wrong for `feature/monetization`:** substantial First
Class + ads work existed in a git stash ("epitaxy: pre-switch"), including 20
untracked files that lived nowhere else. It has since been landed as commit
`9a00fc2` on `feature/monetization`.

| Branch | State |
|---|---|
| `feature/groups` | Genuinely empty — merges from main + an `icon.json` tweak. A named intention. |
| `feature/monetization` | `Monetization/` module (AdsGateway, EntitlementStore, SubscriptionService protocol + StoreKit/mock impls, AdSlotPlanner), `Views/Monetization/` (FirstClassView, AdCard, PromotedSlot), `FeedItem.promoted`, GoogleMobileAds SPM dep, Butler font, tests, and **two spec docs** (2026-07-29 First Class shell, 2026-07-30 ads roadmap — the latter decides First Class + AdMob ship first, sponsored posts deferred). |

The Groups half of the "born behind a flag" argument stands unchanged. For
Monetization, the discipline shifts from *green-field* to *integration*, and the
existing design happens to make that easy:

- `EntitlementStore.isFirstClass` and `AdsGateway.isEligibleForAds` are already
  single choke points — exactly where `FeatureFlag.firstClass` and a
  `promotedSlots` flag belong. Ads eligibility composes naturally:
  `flag on AND NOT isFirstClass`.
- `FeedItem.promoted` is client-inserted (`AdSlotPlanner` decides positions), not
  server wire data — so it needs **no** wire-format forward-compat work, only a
  flag gate at insertion time.
- The `ReferralRewards.milestoneText` call site, commented out pending First
  Class, should come back as a `FeatureFlag.firstClass` check rather than an
  uncomment-and-ship.

Retrofitting flags onto a finished feature is where teams fail; this work is
early enough that the retrofit is three gate-points, not a rewrite.

### What exists after 1.1.1

- Forward-compatible wire decoding for all five enums. New tones, reactions,
  statuses, and onboarding steps can now be added without breaking old clients —
  **the prerequisite for any server-side activation.**
- `get_app_config()` + `RemoteConfig` + `FeatureFlag` with salted percentage
  bucketing and per-install identity for signed-out users.
- Version gate (`recommended` / `required`), verified end-to-end on a signed-out
  device.

### What is missing

1. **The flags are wired to nothing.** `zoomTransition` and `glassEffects`
   resolve correctly and are tested, but no call site reads them. Flipping them
   today does nothing.
2. **No observability.** Sentry is blocked on a DSN. Without crash-free-session
   rate per version and per flag, every percentage rollout below is flown blind —
   you would be ramping 1% → 5% → 30% with no signal to stop on.
3. **No version telemetry.** `device_tokens.app_version` migration is staged but
   unapplied, so "what share of users can read my config?" is unanswerable.
4. **No release cadence.** Shipping on completion, not on a train.

---

## Part 3 — The roadmap

### Phase 0 — Close the loop (before any dark launch)

Nothing below works without these. In order:

1. **Wire the two existing flags** to their call sites. Not for their own sake —
   as the rehearsal. You need to have flipped a flag in production and watched it
   take effect before you bet a feature on it.
2. **Sentry + `app_version`.** The stop signal. Non-negotiable before any
   percentage rollout: a ramp without a metric isn't a staged rollout, it's a
   slow accident.
3. **Turn on App Store Connect phased release.** Free, zero code, and it's the
   binary-level half of the train.
4. **Adopt a cadence.** Even biweekly. Submit whether or not anything big is
   ready. The point is that the next train is always close, which is the *entire*
   mechanism behind "launching without review."

**Exit criteria:** you have flipped a flag in production, seen the effect, and
seen a crash-free-session number attached to a version.

### Phase 1 — The dry run

Before betting Groups on this, rehearse the full loop on something with no
stakes. Best candidate: `glassEffects`.

Sequence: `off` for yourself → `on` for yourself → 10% → watch crash-free
sessions for 48h → 50% → 100% → back to `off` to prove the rollback path works
under real traffic. Rolling *back* is the step everyone skips and the one you
most need to have practiced.

**Exit criteria:** the ramp and the rollback both worked, and you know how long
the signal takes to become readable.

### Phase 2 — Groups, built dark from commit one

The rules, applied from the first commit on `feature/groups`:

- `FeatureFlag.groups` exists and is `false` before any Groups code is written.
- Every Groups entry point is behind it. **Every one** — the tab, deep links,
  push notifications, settings rows, empty states.
- Merge to `main` continuously and ship on the train, inert. Do not accumulate a
  long-lived branch; that reintroduces exactly the big-bang risk flags exist to
  remove.
- New wire values (a `group` post type, a new `BoardWeek.Status`) go out in a
  build **weeks before** anything produces them. This is the interoperability
  wait, and it is the one place where "wait for adoption" is literally required
  rather than merely prudent. Use `device_tokens.app_version` to decide when
  enough clients can read it.

Activation ladder: you (1 user) → your debug friends → one campus at 10% →
that campus at 100% → all campuses. Gate each step on crash-free session rate
and, for Groups specifically, on **moderation volume** — a social surface's
non-linear effect is almost always moderation load, not crashes.

**Server-side prerequisite:** the schema (tables, RLS, RPCs) must ship and be
correct *before* the client flag flips, because the flag only controls the
client. A flag cannot protect you from a missing table.

### Phase 3 — Monetization

Same discipline, three differences that matter:

- **Nothing to dark-launch on the server side.** StoreKit products and App Store
  Connect configuration are Apple-side and have their own review. The flag
  controls *your* paywall, not the products.
- **A billing bug is not rollback-able.** You can turn the paywall off; you
  cannot un-charge someone cleanly. Ramp slower than you would for Groups and
  treat the first cohort as genuinely manual.
- **First Class is already half-built.** `ReferralRewards` computes earned months
  today but its call site is commented out. That commented line *is* the flag
  right now — replace it with a real `FeatureFlag.firstClass` check so the reveal
  is a config change instead of an uncomment-and-ship.

### Adoption — the part that isn't activation

Activation is you flipping a row. Adoption is users on a build that can read it.
These are different problems and the second one is slower.

- **Measure it.** `select app_version, count(*) from device_tokens group by 1`
  is the whole dashboard at your scale. Nothing below is meaningful without it.
- **Expect a long tail.** Some users don't auto-update. `recommended_version` is
  the polite nudge; `min_supported_version` is the hammer, reserved for actively
  harmful builds.
- **Interop features gate on adoption; cosmetic ones don't.** A new tone can flip
  the moment the server can emit it, because old clients now degrade gracefully.
  A new *post type* waits until the reading clients are out there. Know which
  kind you're shipping.
- **The forward-compat work is what buys the option.** Before last night, adding
  a tone would have blanked the feed for every stale client. That's why it came
  first in the plan.

---

## What I would not do

- **Server-driven UI.** One plausible surface, enormous cost, real 2.5.2 risk.
- **A flag per feature forever.** Flags are debt: two code paths, two test
  surfaces. Delete each one within a release or two of reaching 100%. Meta has
  thousands because they have tooling to manage thousands; you do not.
- **Third-party OTA (Patch).** Revisit only with published case history and at a
  scale where review latency has measurable cost.

## Sources

- [Rapid release at massive scale — Engineering at Meta](https://engineering.fb.com/2017/08/31/web/rapid-release-at-massive-scale/)
- [The Dark Launch: How Google & Facebook Release New Features](https://tech.co/news/the-dark-launch-how-googlefacebook-release-new-features-2016-04)
- [Secret to Facebook's Hacker Engineering Culture — LaunchDarkly](https://launchdarkly.com/blog/secret-to-facebooks-hacker-engineering-culture/)
- [Server-Driven UI: A 2026 Guide to Architecture & Examples — WeWeb](https://www.weweb.io/blog/server-driven-ui-guide-architecture-examples)
- [Sending UI over APIs — Builder.io](https://www.builder.io/blog/ui-over-apis)
- [Mobile releases: feature-based or release train? — Runway](https://www.runway.team/blog/mobile-releases-feature-based-or-release-train)
