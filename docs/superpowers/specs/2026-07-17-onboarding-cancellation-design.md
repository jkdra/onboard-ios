# Onboarding cancellation — design

**Date:** 2026-07-17 · **Author:** Claude (autonomous overnight session; user request: "letting users change their mind while creating an account, making sure that applies properly in the database, and a confirmation if they want to cancel account creation")

## Problem

Once a user signs in, they are pushed into the onboarding stack (`OnboardingCoordinator`) with `navigationBarBackButtonHidden()` and **no exit affordance of any kind**. A user who changes their mind mid-account-creation is trapped: no sign-out, no cancel, no back. Their only options are completing onboarding or force-quitting (which restores the session right back into onboarding on next launch). Meanwhile a partial account exists in production: an `auth.users` row plus a `profiles` row (created by the `handle_new_user` trigger), progressively filled in as steps complete.

## Verified backend state (live DB, project `pvgmcqokvcqsztaeqcpe`, checked 2026-07-17 via MCP)

- `delete_own_account()` exists, `SECURITY DEFINER`, executable by `authenticated` only. Deletes: avatars in storage, posts, comments, reactions, comment_votes, board_members, profiles, and the `auth.users` row.
- `device_tokens` and `school_email_otps` FK to `auth.users` **ON DELETE CASCADE** — cleaned automatically. (The comment in `SupabaseAuthService.signOut` claiming this is accurate.)
- All other user tables cascade from `profiles` (blocks, follows, user_settings, user_reaction_counts, push_notification_ledger, reports).
- **Gap:** `waitlist.profile_id` is `ON DELETE SET NULL`. Deleting a not-yet-admitted user orphans their waitlist row (school email + board), leaving a ghost entry an admin could "admit" — the admission email would go to an email whose account no longer exists.

## Design

### 1. Backend (one migration, applied via MCP + mirrored locally)

Extend `delete_own_account()` with:

```sql
delete from public.waitlist where profile_id = uid and admitted_at is null;
```

before the `profiles` delete (while `profile_id` is still populated). Admitted rows are intentionally kept — an admitted seat is a historical record and the SET NULL behavior preserves it. Apply with `apply_migration` (MCP), then mirror the file into `onboard-ios/supabase/migrations/` with the ledger's version so `supabase db push` stays consistent.

### 2. iOS — cancel affordance

A new `OnboardingCancelModifier` (`Views/Onboarding/OnboardingCancelButton.swift`) applied once in `OnboardingCoordinator` around the step-view switch, giving every step a `topBarTrailing` **Cancel** button (text, secondary style — quiet, since the primary journey is forward).

Tapping it opens a **confirmation dialog**:

- **Title:** "Cancel account creation?"
- **"Sign out & finish later"** — keeps the partial account; `auth.signOut()`. Next sign-in resumes exactly where they left off (`effectiveOnboardingStep` already handles this).
- **"Delete my info & cancel"** (destructive) — if the session has a linked Apple identity, run the `AppleSignInCoordinator.requestAuthorization()` → `auth.revokeApple(authorizationCode:)` sequence first (same as `DeleteAccountView`), then `auth.deleteAccount()` (which also disconnects Google locally). Wipes the partial account server-side via `delete_own_account`.
- **"Keep going"** (cancel role).

No second "type your username" gate here (unlike `DeleteAccountView`): mid-onboarding there may be no username yet, and the account has no content — one confirmation with an explicit destructive label is proportionate.

While deleting: the step content is disabled under a thin overlay spinner; failures surface via the existing `PresentableAlertError` alert.

### 3. Why no store changes

`auth.deleteAccount()` / `auth.signOut()` already flip `auth.state`; `RootView.syncSessionState()` then calls `onboarding.reset()` (clearing the per-user `OnboardingStatusCache`) and `OnboardingCoordinator` pops `path = []` on `isSignedIn == false`. The user lands back on `SignInView` with clean state. No new store surface is needed; the modifier is self-contained view logic reusing `AuthStore`.

### 4. Out of scope (documented follow-ups)

- Back-navigation to *edit* earlier answers (e.g. change birthday after submitting). The RPCs would tolerate it (each sets `onboarding_step` forward from its own step), but the coordinator's path logic only grows and the UX needs design; not attempted overnight.
- The waitlist "ghost admit" race for *already-admitted* users deleting accounts — pre-existing, unrelated to cancellation.

## Testing

- Existing `OnboardingStoreTests` / auth tests must keep passing (build + full test run).
- The dialog/deletion flow is view-level; verified by building and driving the mock-mode app (Secrets.xcconfig absent → MockAuthService/MockOnboardingService) in the simulator.
- Backend change verified by re-querying the function body via MCP after `apply_migration`, plus advisors re-run.

---

## Implementation addendum (written post-implementation, same session)

Shipped as designed, plus three things found along the way:

1. **The unit test suite was completely broken** before this session: `PRODUCT_NAME` had been changed to `"On Board: Your Community Board"` (colon in an executable name) while `TEST_HOST` pointed at `"On Board: The Community Board"` — mismatched with the product *and* with each other, so `xcodebuild test` failed before running anything. Fixed by restoring `PRODUCT_NAME = "On Board"` (the home-screen name was always `INFOPLIST_KEY_CFBundleDisplayName = "On Board"`; the App Store listing name lives in App Store Connect metadata, not `PRODUCT_NAME`) and pointing `TEST_HOST` at `On Board.app`. 79 tests / 31 suites green after the fix.
2. **Pre-existing title overlap on every onboarding step** (verified present without the new toolbar): the iOS 26 SDK draws the large navigation title over the first lines of scroll content. Fixed with `.navigationBarTitleDisplayMode(.inline)` applied alongside the cancel toolbar in the coordinator. Verified visually in the simulator before/after.
3. **Verification**: backend change confirmed live via MCP (function body re-queried; security advisors re-run — no new findings, only the documented accepted set). iOS verified by full test run + driving the mock-mode app in the simulator with a seeded fresh-user session (`-mock.auth.session <data>`), confirming the Cancel button renders on the Birthday step and the layout fix landed. The confirmation dialog itself and the Apple-revoke path were not UI-driven (no tap automation available); they reuse the exact sequence shipping in `DeleteAccountView`, and the store paths are pinned by the new `OnboardingCancellationTests`.
