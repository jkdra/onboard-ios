# On Board — Whole-Repo Polish Audit (2026-08-08)

Six parallel read-only investigations: dead code, modularization, schema↔client
drift, cross-app parity, launch blockers + security, and polish research.
Nothing has been changed; every item below awaits sign-off. Ranked by urgency.

---

## P0 — Blockers (fix before this branch merges / before launch)

1. **Rich-text branch cannot post against the live DB.**
   `SupabaseBoardService+Posts.swift` (createPost ~:101, updatePost ~:174)
   writes `title: ""`, but live `posts` still enforces
   `posts_title_not_blank CHECK (char_length(btrim(title)) > 0)`. Every post
   create/edit from `feature/rich-text-posts` throws a check violation in prod.
   The "pre-migration wire shape" comment anticipates a server migration that
   does not exist yet. → Land the title-collapse migration (preview branch
   first) before merge/TestFlight, or derive a non-blank title client-side.

2. **SECURITY (HIGH, new): anon can read all posts and comments.**
   Confirmed empirically (`set local role anon` → posts 22, comments 16).
   The `posts read filtered` / `comments read filtered` SELECT policies are
   role `{public}` and their non-hidden disjunct needs no `auth.uid()`; anyone
   with the shipped anon key can `GET /rest/v1/posts?select=*`. The apparent
   gating via `posts_with_meta` is an accident of a profiles join. → Scope
   those SELECT policies to `authenticated` (or add `auth.uid() is not null`).

3. **Two Auth-dashboard confirmations (Jawad, not scriptable):**
   - SMTP → Resend migration state (was THE launch blocker; not inspectable
     via MCP).
   - Leaked-password (HIBP) protection — advisor confirms still **disabled**;
     app ships `SetPasswordView`.

4. **Unpushed sibling work, one deploy-relevant:**
   - `onboard-web` main ahead 2 (incl. AASA/universal-link fallback + real
     App Store id `id6782297168` replacing the TestFlight placeholder) —
     affects live invite links; push + deploy.
   - `onboard-admin` main ahead 6 (Remote Config page, campus demand ledger,
     auth-gated push test) — push + deploy.
   - `onboard-android` branch `onboarding` has **no upstream** + dirty
     CLAUDE.md/TODO.md — set upstream, commit or stash.

---

## P1 — Quick wins (small, near-zero risk)

**Dead code (~245 LOC + 2 SPM links; all verified, dev harnesses excluded):**
- `SignInMethodKind` enum + `AuthSession.signInMethodKinds` (CERTAIN).
- `BoardSchedule.daysInWeek/weekStarts/isSameDay` (CERTAIN).
- `BoardStore.loadOfflinePreviewData()` (CERTAIN — "previews only" per its
  doc, but nothing calls it; `devSetCountdown` next door IS used).
- `BirthdayCelebration.monthDayString` (CERTAIN).
- Template UITest files `On_BoardUITests.swift` + `On_BoardUITestsLaunchTests.swift` (78 LOC).
- `FontStylePreview.swift` (LIKELY — design-reference gallery; judgment call).
- `LegalDocument.docType`/`requiresReacceptance` (LIKELY — mind the future
  "terms changed" prompt intent).
- SPM: `GoogleSignInSwift` product linked but never imported; `Auth` product
  redundant (re-exported by `Supabase`).
- **`Profile.displayNameOrHandle`: NOT a bug, but adopt it, don't delete it** —
  ProfileView:274, SettingsProfilePreview, ProfileReadContent:134 reimplement
  the exact fallback inline; replace those three with the helper.
- Keep: the `TODO(launch)` commented block in OnboardingWaitlistStepView
  (First Class rewards — deliberate).

**Mechanical moves (modularization F5b/F9 + hygiene):**
- `extension UIApplication.safeAreaInsets` out of `PostImageCropView.swift:701`
  → `Extensions/UIApplication+SafeArea.swift` (consumed cross-feature).
- `WelcomeCelebration` → `Utilities/` (beside its twin `BirthdayCelebration`).
- `PendingReferralCode` → own file (its extension file already exists);
  `PostGeometryID` → own file.
- Delete dead `import Supabase` in ProfileView, NewPostView,
  OnboardingProfileStepView.
- `Models/Tag.swift:13` still documents the removed `search_tags` call.

**CLAUDE.md corrections (iOS):**
- References to `BoardStore+Interactions.swift` → now split into
  `+Posts/+Comments/+Reactions/+Moderation`.
- "How a flag reaches its call site" bullet duplicated verbatim.
- Push-cron table: add `moderation-drain` (every minute), `rotate-board-weeks`
  (hourly), `delete-unused-tags-3d` (daily).
- Accepted-advisor list: add `get_invite_inviter` (anon SECURITY DEFINER —
  intentional for web invites) and the six newer rls_no_policy tables
  (`archived_reported_posts`, `moderation_flags`, `moderation_log`,
  `prompt_queue`, `school_domain_requests`, `user_reaction_counts`).
- Sibling docs: admin CLAUDE.md omits its Moderation/Auto-Mod + Prompts pages;
  web CLAUDE.md is empty boilerplate; Android TODO overstates onboarding
  done-ness (missing birthday/graduation/profanity steps untracked).

---

## P2 — Structural splits (house conventions, ranked value÷effort)

1. **ContentView.swift (734)** → `+Views`/`+Logic` split (hub view, most
   diffed). Keep `@Namespace`/state in core — zoom-namespace rules bind.
   Check `triggerBoardReset` (531–606) for overlap with `BoardStore+Refresh`.
2. **MarkupTextEditor.swift (689)** → 4 files along its own MARKs
   (`MarkupEditorController` / representable / `MarkupStyler` /
   `ComposerToolbar`). Time against the active branch.
3. **SignInView.swift (597)** → `+Logic` (helpers block :398–597 is ready-made;
   `+Social` precedent exists). OTP-reuse comment travels with code.
4. **AccountSecuritySettingsView (446)** → `+Views` (14 row builders).
5. **PostImageCropView (710)** → `+Views`/`+Logic` + `CropAspectOption` file.
6. **BoardStore.swift core (619)** → extract Configuration (182–348) and Feed
   composition (356–407) to `BoardStore+Feed.swift`-style extensions.
7. **SupabaseAuthService (496)** → `+Linking/+Social/+Password` mirroring
   SupabaseBoardService's idiom.
8. **GridCard.swift (414)** → `FeedGridCard` + sticker pill to own files
   (pure moves — matchedTransitionSource padding trick must not restructure).
9. **On_BoardTests.swift (1918)** → one file per suite + `Fixtures.swift`.
10. **LegalService** (only true layering violation): lives in
    `Models/LegalDocument.swift`, calls Supabase directly — move to
    `Supabase/`, ideally protocol+mock+factory like the other services.
11. Directory: `RootView` beside `On_BoardApp`; `OnBoardImagePipeline` →
    `Utilities/`; pick one home for the two crop views.
12. Glass hand-roll consolidation (OnboardingProgressBar, CountdownCard,
    HostSpeechBubble, GridCard vs `GlassBackground`) — lowest confidence,
    needs sim verification per house rule; do last or skip.

---

## P3 — Schema / backend follow-ups (non-blocking)

- **Legal acceptance unwired**: `accept_legal_documents` RPC + version columns
  live and guarded, but iOS never calls it — terms are shown, acceptance never
  recorded. Wire at pledge/legal screens or deliberately drop the columns.
- Orphaned RPCs from iOS: `search_tags` (+ orphaned `Tag` model),
  `fetch_posts_by_author`, `fetch_active_board_posts`, `fetch_tags_for_post` —
  confirm no other client uses them before dropping.
- `admin-notify-user` edge function referenced by nothing in this repo
  (admin-portal-only? confirm).
- Moderation: text tier live (Claude Haiku judge, pgmq, drain cron; 19 log
  rows, 0 flags — confirm `MODERATION_SHADOW` intent). **Image/CSAM tier
  still unbuilt** (no R2 move, judge is text-only).
- Perf INFO only: 3 unindexed admin-side FKs; 8 unused indexes. Not
  launch-relevant.
- Everything else clean: all 31 client RPCs exist; enums match exactly in both
  directions; `notify_push` switch coverage complete (v27); settings payload
  full-upsert intact; RLS initplan hygiene perfect.

---

## P4 — Cross-app parity (Android = strict subset, stalled at Phase 4/7)

Post-onboarding Android is a placeholder (`FeedPlaceholder.kt`). Ranked port
backlog: ① board feed + live BoardService (L) → ② post detail + comments (L)
→ ③ reactions with the supersession pattern (M) → ④ composer + Storage
uploads (M–L) → ⑤ **report/block UI (M — Play-policy launch blocker for
UGC)** → ⑥ missing onboarding steps: birthday, graduation, profanity —
silently divergent and untracked in TODO.md (S–M) → ⑦ referral ladder UI
(S; web side live) → ⑧ remote config + version gate (M) → ⑨ push/FCM
(L; Edge Function is APNs-only today — needs an FCM dispatch path) →
⑩ profiles/follow/Pop Score, archive, deep links (L).
Web: referral/invite flow current; terms page (Jul 14) predates the referral
correction — review. Changelog shows current version only (documented limit).
Admin: coverage exceeds its docs (Auto-Mod queue + log, Prompts) — pipeline
work remains, not portal UI.

---

## P5 — Polish backlog (research-derived, 30 items; top picks by fit)

Full tiered list with citations lives in the research report (session
transcript). The five best identity-fits:

1. **Monday-open ritual + board-clearing Live Activity countdown** (BeReal's
   synchronized-moment engine applied to a weekly cadence).
2. **Host-narrated weekly mini-recap at board close** (Spotify's weekly
   mini-Wrapped; doubles as the archive's front door + share card).
3. **Push voice system**: all five cron pushes rewritten in The Host's voice,
   `clearing-soon` as the "save" tier; 2/day cap. Highest ROI-per-hour.
4. **Haptic vocabulary** (~6 named events via `.sensoryFeedback`; per-reaction
   CoreHaptics signatures as the signature verb).
5. **Host-driven empty states** (fresh Monday board: "Someone has to go
   first."), plus reveal-on-open authorship beat, `.numericText()` count
   odometers, post-send masonry drop-in celebration.
Cautions: mascot in ≤5 surfaces, never in composing/moderation; no indefinite
symbol effects (XCUITest idle landmine); new toggle-style interactions need
the in-flight supersession pattern.

---

*Generated from six parallel audit agents; live-DB findings verified
SELECT-only against the production Supabase project on 2026-08-08.*
