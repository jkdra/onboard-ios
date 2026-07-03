# Auth & Board-Loading Hardening — Design

**Date:** 2026-07-03
**Status:** Approved (discussed and folded into one batch with Jawad)

## Context

Investigation confirmed the Supabase backend is healthy (approved profile has
`board_id` → Irvine Valley College with an active `board_weeks` row;
`get_onboarding_status` returns `board_id`/`board_name` correctly). All failures
are client-side, plus one missing RPC and one storage-policy interaction.

Verified evidence:

- `storage.objects` is empty — no upload has **ever** succeeded in `avatars` or
  `post-images`. The RLS INSERT policy passes when simulated directly as the
  user; the avatar upload's `upsert: true` is the differentiator (Supabase
  storage requires INSERT **and** UPDATE permission for upsert; only INSERT and
  DELETE policies exist).
- `list_accessible_boards` does not exist in the database; the app calls it and
  silently swallows the 404.
- `OnboardingStore.refreshIfOnline()` early-returns once loaded, so the
  scenePhase-foreground refresh in RootView is a no-op — waitlist approval is
  invisible until cold relaunch.
- `SampleBoardID.main` (`…-0001`, the production "On Board Dev" board) is used
  as a live fallback in `BoardStore.refresh` and in `BoardWeek`'s decoder.
- `reactions.id` / `board_members.id` PostgREST errors are NOT from the iOS app
  (no such queries exist in it) — likely admin tooling. Out of scope.

## 1. Board loading

- **Staleness-window refresh:** `OnboardingStore` records the time of the last
  successful fetch. `refreshIfOnline()` re-fetches when the status is older
  than ~60s (instead of never). Cold-launch and submit paths unchanged.
- **Waitlist polling:** while the waitlist step is visible, poll
  `onboarding.refresh()` on a modest interval (~30–60s) so admin approval lands
  without user action. Keep it scoped to that screen; cancel on disappear.
- **Kill dev-board fallbacks in live paths:**
  - `BoardStore.refresh` bails (no-op) when `currentBoardId` is nil rather than
    fetching `SampleBoardID.main`.
  - `BoardWeek.init(from:)` requires `boardId` — no silent substitution.
  - Preview/mock fixtures keep using `SampleBoardID.main`; only live paths change.
- **`list_accessible_boards` migration:** new timestamped migration creating
  the RPC (security definer, `board_members` ⋈ `boards` for `auth.uid()`),
  returning `id`, `name`. Push through the normal migration flow.
- **BoardListView renders `accessibleBoards`:** list all accessible boards
  (falling back to `currentBoard` alone if empty), selection drives
  `store.setBoard` + `store.refresh`.

## 2. Sign-in methods & unlink safety

- **Identity-derived method counting:** `AuthSession` gains
  `hasEmailIdentity` / `hasPhoneIdentity`, derived from the Supabase
  `userIdentities()` list (`email` / `phone` providers). `signInMethodKinds`,
  `remainingSignInMethodCount`, `hasLinked` use identities only — never the
  OAuth-copied `user.email` / `user.phone`. Both live and mock services stay in
  sync (protocol conventions per CLAUDE.md).
- **Sectioned UI** in `AccountSecuritySettingsView`:
  - "Sign-In Methods": phone, email — linked rows show detail + a **Change**
    action; unlinked rows show **Link**.
  - "Third-Party": Apple, Google.
- **Linked third-party treatment:**
  - Unlinkable → grayed "Linked" `Menu` with a sole destructive **Unlink**
    action → existing confirmation alert ("You won't be able to sign in with
    this method unless you link it again.").
  - Sole method → disabled grayed "Linked" with "connect another method to
    unlink" explanation; no menu.
- **Change email/phone:** reuse `LinkSignInMethodView` with a change mode; the
  server flow already exists (`UserAttributes` update + `emailChange` /
  `phoneChange` OTP verification).
- No phone/email unlink (Supabase can't cleanly remove them; Change covers it).

## 3. Storage uploads

- Avatar upload (`OnboardingProfileStepView`): `upsert: false` (paths are
  unique UUIDs; matches `PostImageUploader`).
- Optional hardening: owner-scoped UPDATE policy migration on `storage.objects`
  for both buckets.
- Verify post-image upload end-to-end after (none has ever succeeded).

## 4. Auth hardening for existing accounts

- **Apple name clobber:** `signInWithApple` writes `display_name` only when the
  current profile name is empty/provisional — protects returning users who
  revoked & re-authorized Apple.
- **Offline restore:** `restoreSession` distinguishes connectivity failure from
  "no session". On connectivity failure, surface a retryable state routed to
  `OfflineGateView` (covers path-monitor-says-online-but-requests-fail);
  auto-retry when connectivity restores. Never dump a signed-in user onto
  SignInView because of a network blip.
- **Resilient sign-out:** if the network sign-out fails, clear the local
  session anyway (local sign-out scope) so the user isn't stranded in `.failed`.

## 5. Tests

- Method counting from identities (incl. OAuth-only user with copied email).
- Waitlist → complete transition & staleness refresh behavior.
- `BoardWeek` decode strictness (missing `board_id` fails, not silently mapped).
- Restore-session offline classification.

## Out of scope (flagged)

- Email OTP `shouldCreateUser` (typo'd email at sign-in silently creates an
  account) — product decision pending.
- Admin tooling's `reactions.id` / `board_members.id` query errors.
- Passkeys / 2FA placeholders.
